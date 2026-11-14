// Security rules tests, run against the Firestore emulator (see package.json).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, collection, addDoc, query, where, writeBatch, increment } from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-bizpos',
    firestore: { rules: readFileSync(new URL('./firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8080 },
  });
});

after(async () => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'admins/boss'), { role: 'super' });
    await setDoc(doc(db, 'shops/s1'), { ownerUid: 'alice', name: 'Alice Mart', plan: 'free', status: 'active', devices: {} });
    await setDoc(doc(db, 'shops/s2'), { ownerUid: 'bob', name: 'Bob Store', plan: 'pro', status: 'active', features: ['voice'] });
    await setDoc(doc(db, 'packages/p1'), { name: 'Pro', features: ['voice'] });
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

test('owner reads own shop but not someone else', async () => {
  await assertSucceeds(getDoc(doc(as('alice'), 'shops/s1')));
  await assertFails(getDoc(doc(as('alice'), 'shops/s2')));
  await assertFails(getDoc(doc(anon(), 'shops/s1')));
});

test('owner cannot give themselves a paid plan', async () => {
  const db = as('alice');
  await assertFails(updateDoc(doc(db, 'shops/s1'), { plan: 'pro' }));
  await assertFails(updateDoc(doc(db, 'shops/s1'), { features: ['voice'] }));
  await assertFails(updateDoc(doc(db, 'shops/s1'), { expiresAt: 9999999999999 }));
  await assertFails(updateDoc(doc(db, 'shops/s1'), { status: 'active', adFree: true }));
  await assertSucceeds(updateDoc(doc(db, 'shops/s1'), { name: 'Alice Mart 2', 'devices.ABCD1234': { name: 'android' } }));
});

test('new shops must start free and belong to the creator', async () => {
  const db = as('carol');
  await assertFails(setDoc(doc(db, 'shops/s3'), { ownerUid: 'carol', name: 'C', plan: 'pro', status: 'active' }));
  await assertFails(setDoc(doc(db, 'shops/s3'), { ownerUid: 'alice', name: 'C', plan: 'free', status: 'active' }));
  await assertFails(setDoc(doc(db, 'shops/s3'), { ownerUid: 'carol', name: 'C', plan: 'free', status: 'active', features: ['voice'] }));
  await assertSucceeds(setDoc(doc(db, 'shops/s3'), { ownerUid: 'carol', name: 'C', plan: 'free', status: 'active', devices: {} }));
});

test('super admin can manage every shop and package', async () => {
  const db = as('boss');
  await assertSucceeds(getDoc(doc(db, 'shops/s1')));
  await assertSucceeds(updateDoc(doc(db, 'shops/s1'), { plan: 'pro', features: ['voice'], expiresAt: 1 }));
  await assertSucceeds(setDoc(doc(db, 'packages/p2'), { name: 'New' }));
  await assertSucceeds(setDoc(doc(db, 'subscriptions/x'), { ownerUid: 'alice', shopId: 's1', amount: 1000 }));
  await assertSucceeds(setDoc(doc(db, 'settings/app'), { footer: 'Powered by BizPOS' }));
});

test('only admins write packages, settings and subscriptions', async () => {
  const db = as('alice');
  await assertSucceeds(getDoc(doc(anon(), 'packages/p1')));
  await assertFails(setDoc(doc(db, 'packages/p1'), { name: 'Free Pro' }));
  await assertFails(setDoc(doc(db, 'settings/app'), { footer: 'hacked' }));
  await assertFails(setDoc(doc(db, 'subscriptions/x'), { ownerUid: 'alice', amount: 0 }));
  await env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), 'subscriptions/y'), { ownerUid: 'alice', amount: 500 }));
  await assertSucceeds(getDoc(doc(db, 'subscriptions/y')));
  await assertFails(getDoc(doc(as('bob'), 'subscriptions/y')));
});

test('nobody can make themselves super admin', async () => {
  await assertFails(setDoc(doc(as('alice'), 'admins/alice'), { role: 'super' }));
  await assertFails(updateDoc(doc(as('boss'), 'admins/boss'), { role: 'owner' }));
  await assertSucceeds(updateDoc(doc(as('boss'), 'admins/boss'), { totpEnabled: true }));
  await assertFails(getDoc(doc(as('alice'), 'admins/boss')));
});

test('blocked shops cannot be edited by the owner', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => updateDoc(doc(ctx.firestore(), 'shops/s1'), { status: 'blocked' }));
  await assertFails(updateDoc(doc(as('alice'), 'shops/s1'), { name: 'x' }));
});

test('upgrade requests: owners create for their own shop only', async () => {
  const db = as('alice');
  await assertSucceeds(addDoc(collection(db, 'requests'), { ownerUid: 'alice', shopId: 's1', packageId: 'p1', status: 'pending' }));
  await assertFails(addDoc(collection(db, 'requests'), { ownerUid: 'alice', shopId: 's2', packageId: 'p1', status: 'pending' }));
  await assertFails(addDoc(collection(db, 'requests'), { ownerUid: 'alice', shopId: 's1', packageId: 'p1', status: 'approved' }));
});

test('users documents are private', async () => {
  await assertSucceeds(setDoc(doc(as('alice'), 'users/alice'), { email: 'a@x.com', name: 'A', shopId: 's1' }));
  await assertFails(getDoc(doc(as('bob'), 'users/alice')));
  await assertFails(setDoc(doc(as('bob'), 'users/alice'), { email: 'b@x.com' }));
  await assertSucceeds(getDoc(doc(as('boss'), 'users/alice')));
  await assertFails(deleteDoc(doc(as('bob'), 'users/alice')));
});

test('super admin creates a company; owner joins it with the code', async () => {
  await assertSucceeds(setDoc(doc(as('boss'), 'shops/c1'), { ownerUid: '', ownerEmail: 'dave@example.com', name: 'Dave Traders', plan: 'pro', status: 'active', devices: {} }));
  // Owners cannot create unowned or pre-paid companies themselves.
  await assertFails(setDoc(doc(as('eve'), 'shops/c2'), { ownerUid: '', name: 'X', plan: 'free', status: 'active' }));
  // Anyone with the code can open it and claim it, changing only owner fields.
  await assertSucceeds(getDoc(doc(as('dave'), 'shops/c1')));
  await assertFails(updateDoc(doc(as('dave'), 'shops/c1'), { ownerUid: 'dave', plan: 'lifetime' }));
  await assertFails(updateDoc(doc(as('dave'), 'shops/c1'), { ownerUid: 'someone-else' }));
  await assertSucceeds(updateDoc(doc(as('dave'), 'shops/c1'), { ownerUid: 'dave', ownerEmail: 'dave@example.com' }));
  // Once claimed nobody else can take it or read it.
  await assertFails(updateDoc(doc(as('eve'), 'shops/c1'), { ownerUid: 'eve' }));
  await assertFails(getDoc(doc(as('eve'), 'shops/c1')));
});

test('verified owner finds the company made for their email', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'shops/c3'), { ownerUid: '', ownerEmail: 'frank@example.com', name: 'Frank Co', plan: 'free', status: 'active' });
  });
  const verified = env.authenticatedContext('frank', { email: 'frank@example.com', email_verified: true }).firestore();
  const unverified = env.authenticatedContext('mallory', { email: 'frank@example.com', email_verified: false }).firestore();
  const q = (db) => query(collection(db, 'shops'), where('ownerUid', '==', ''), where('ownerEmail', '==', 'frank@example.com'));
  await assertSucceeds(getDocs(q(verified)));
  await assertFails(getDocs(q(unverified)));
});

test('online store: paid shops publish, website reads, customers order', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'shops/paid1'), { ownerUid: 'gina', name: 'Gina Store', plan: 'pro-monthly', status: 'active', expiresAt: 4102444800000 });
  });
  const card = (extra) => ({ shopId: 'paid1', ownerUid: 'gina', name: 'Gina Store', paidUntil: 4102444800000, published: true, adminHidden: false, ...extra });
  // A free shop cannot go online; a paid one can.
  await assertFails(setDoc(doc(as('alice'), 'storefronts/s1'), { shopId: 's1', ownerUid: 'alice', paidUntil: 0, published: true, adminHidden: false }));
  await assertFails(setDoc(doc(as('gina'), 'storefronts/paid1'), card({ paidUntil: 0 })));
  await assertFails(setDoc(doc(as('gina'), 'storefronts/paid1'), card({ adminHidden: true })));
  await assertSucceeds(setDoc(doc(as('gina'), 'storefronts/paid1'), card()));
  await assertSucceeds(setDoc(doc(as('gina'), 'storefronts/paid1/items/p1'), { name: 'Rice', price: 100 }));
  await assertFails(setDoc(doc(as('alice'), 'storefronts/paid1/items/p2'), { name: 'Hack', price: 1 }));
  // The owner cannot unhide a store the super admin hid.
  await assertSucceeds(updateDoc(doc(as('boss'), 'storefronts/paid1'), { adminHidden: true }));
  await assertFails(updateDoc(doc(as('gina'), 'storefronts/paid1'), { adminHidden: false }));
  await assertSucceeds(updateDoc(doc(as('boss'), 'storefronts/paid1'), { adminHidden: false }));
  // Anyone reads the public store and its products; only the admin features products.
  await assertSucceeds(getDoc(doc(anon(), 'storefronts/paid1')));
  await assertSucceeds(getDocs(query(collection(anon(), 'storefronts'), where('published', '==', true), where('adminHidden', '==', false))));
  await assertSucceeds(getDocs(collection(anon(), 'storefronts/paid1/items')));
  await assertFails(setDoc(doc(as('gina'), 'featured/x'), { kind: 'hot' }));
  await assertSucceeds(setDoc(doc(as('boss'), 'featured/x'), { kind: 'hot' }));
  // A customer without an account places an order; only the owner reads it.
  const order = { shopId: 'paid1', ownerUid: 'gina', shopName: 'Gina Store', currency: 'Rs', items: [{ id: 'p1', name: 'Rice', price: 100, qty: 2 }],
    total: 200, customerName: 'Zara', customerPhone: '03001234567', address: 'Lahore', note: '', status: 'new' };
  await assertSucceeds(setDoc(doc(anon(), 'orders/o1'), order));
  await assertFails(setDoc(doc(anon(), 'orders/o2'), { ...order, status: 'delivered' }));
  await assertFails(setDoc(doc(anon(), 'orders/o3'), { ...order, ownerUid: 'mallory' }));
  await assertSucceeds(getDoc(doc(as('gina'), 'orders/o1')));
  await assertSucceeds(updateDoc(doc(as('gina'), 'orders/o1'), { status: 'confirmed' }));
  await assertFails(updateDoc(doc(as('gina'), 'orders/o1'), { total: 1 }));
});

test('shopper accounts and BizPOS coins', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'settings/app'), { coinsEnabled: true, coinsPerHundred: 2, coinValue: 1, coinsMaxPercent: 10 });
    await setDoc(doc(db, 'shops/paid2'), { ownerUid: 'hana', name: 'Hana Mart', plan: 'pro', status: 'active', expiresAt: 0 });
    await setDoc(doc(db, 'storefronts/paid2'), { shopId: 'paid2', ownerUid: 'hana', name: 'Hana Mart', published: true, adminHidden: false, paidUntil: 0 });
  });
  const shopper = as('sam');
  // Shoppers start with 0 coins and cannot give themselves coins.
  await assertFails(setDoc(doc(shopper, 'shoppers/sam'), { name: 'Sam', coins: 50 }));
  await assertSucceeds(setDoc(doc(shopper, 'shoppers/sam'), { name: 'Sam', phone: '03001112222', coins: 0 }));
  await assertFails(updateDoc(doc(shopper, 'shoppers/sam'), { coins: 100 }));
  await assertSucceeds(updateDoc(doc(shopper, 'shoppers/sam'), { address: 'Lahore' }));

  const base = { shopId: 'paid2', ownerUid: 'hana', shopName: 'Hana Mart', currency: 'Rs', items: [{ id: 'x', name: 'Oil', price: 1000, qty: 1 }],
    total: 1000, customerName: 'Sam', customerPhone: '03001112222', address: '', note: '', status: 'new', customerUid: 'sam' };
  await assertSucceeds(setDoc(doc(shopper, 'orders/s1'), base));
  // Someone else cannot put Sam's uid on an order.
  await assertFails(setDoc(doc(as('eve'), 'orders/s2'), base));
  // Shopper sees their own orders.
  await assertSucceeds(getDocs(query(collection(shopper, 'orders'), where('customerUid', '==', 'sam'))));

  // Hana delivers and gives coins: at most total/100 * 2 = 20.
  const hana = as('hana');
  const award = async (coins, orderId = 's1') => {
    const b = writeBatch(hana);
    b.update(doc(hana, `orders/${orderId}`), { status: 'delivered', coinsAwarded: coins });
    b.set(doc(hana, `coinAwards/${orderId}`), { uid: 'sam', coins, shopId: 'paid2' });
    b.update(doc(hana, 'shoppers/sam'), { coins: increment(coins), lastAward: orderId });
    return b.commit();
  };
  await assertFails(award(500));
  await assertSucceeds(award(20));
  // The same order cannot give coins twice.
  await assertFails(award(20));

  // Spending: 10 coins = Rs 10 off (max 10% of 1000), balance goes down in the same write.
  const spend = (coins, discount, id) => {
    const b = writeBatch(shopper);
    b.set(doc(shopper, `orders/${id}`), { ...base, coinsUsed: coins, coinDiscount: discount });
    b.update(doc(shopper, 'shoppers/sam'), { coins: increment(-coins), lastOrder: id });
    return b.commit();
  };
  await assertFails(spend(10, 50, 'c1'));
  await assertFails(spend(30, 30, 'c2'));
  await assertSucceeds(spend(10, 10, 'c3'));
  // Only 10 coins left: spending 15 would go negative.
  await assertFails(spend(15, 15, 'c4'));
  // Coins without the balance change are refused.
  await assertFails(setDoc(doc(shopper, 'orders/c5'), { ...base, coinsUsed: 5, coinDiscount: 5 }));
  // Anyone with the order number can track it.
  await assertSucceeds(getDoc(doc(anon(), 'orders/c3')));
});

test('product photos: owner adds small ones, others cannot', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'storefronts/s1'), { ownerUid: 'alice', shopId: 's1', published: true, adminHidden: false });
    await setDoc(doc(ctx.firestore(), 'storefronts/s1/items/i1'), { name: 'Tea' });
  });
  const small = 'data:image/jpeg;base64,' + 'A'.repeat(1000);
  await assertSucceeds(setDoc(doc(as('alice'), 'storefronts/s1/items/i1/photos/a'), { data: small, order: 0 }));
  await assertFails(setDoc(doc(as('alice'), 'storefronts/s1/items/i1/photos/b'), { data: 'A'.repeat(700000), order: 1 }));
  await assertFails(setDoc(doc(as('bob'), 'storefronts/s1/items/i1/photos/c'), { data: small, order: 2 }));
  await assertSucceeds(getDoc(doc(anon(), 'storefronts/s1/items/i1/photos/a')));
  await assertSucceeds(deleteDoc(doc(as('alice'), 'storefronts/s1/items/i1/photos/a')));
});

test('announcements and offers: everyone reads, only admins write', async () => {
  await assertSucceeds(setDoc(doc(as('boss'), 'announcements/a1'), { title: 'Eid sale', active: true, audience: 'all' }));
  await assertFails(setDoc(doc(as('alice'), 'announcements/a2'), { title: 'spam', active: true }));
  await assertSucceeds(getDoc(doc(anon(), 'announcements/a1')));
  await assertFails(setDoc(doc(as('alice'), 'offers/o9'), { title: 'free forever', active: true }));
});

const claim = (db, { shop = 's1', offer = 'o1', days = 15, pkgFields = {} } = {}) => {
  const b = writeBatch(db);
  b.update(doc(db, `shops/${shop}`), {
    plan: 'p1', planName: 'Pro', features: ['voice'], adFree: true, maxProducts: 0, onlineProducts: 3,
    expiresAt: Date.now() + days * 86400000, offer, ...pkgFields,
  });
  b.set(doc(db, `offerClaims/${shop}_${offer}`), { shopId: shop, offerId: offer, ownerUid: 'alice' });
  return b.commit();
};

test('offer: a free shop with enough products claims it once', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, 'offers/o1'), { title: '15 days Pro', packageId: 'p1', days: 15, minProducts: 50, active: true, startAt: Date.now() - 1000, endAt: 0 });
    await setDoc(doc(d, 'offers/o2'), { title: 'old', packageId: 'p1', days: 15, minProducts: 0, active: false, startAt: 0, endAt: 0 });
  });
  const db = as('alice');
  // Not enough products yet.
  await assertFails(claim(db));
  await updateDoc(doc(db, 'shops/s1'), { stats: { products: 60 } });
  // More days than the offer, other features, or an inactive offer: refused.
  await assertFails(claim(db, { days: 90 }));
  await assertFails(claim(db, { pkgFields: { features: ['voice', 'reports'] } }));
  await assertFails(claim(db, { offer: 'o2' }));
  // Plan change without the claim record: refused.
  await assertFails(updateDoc(doc(db, 'shops/s1'), { plan: 'p1', planName: 'Pro', features: ['voice'], adFree: true, maxProducts: 0, onlineProducts: 3, expiresAt: Date.now() + 86400000, offer: 'o1' }));
  await assertSucceeds(claim(db));
  // Second time: refused.
  await env.withSecurityRulesDisabled(async (ctx) => updateDoc(doc(ctx.firestore(), 'shops/s1'), { plan: 'free', expiresAt: 1 }));
  await assertFails(claim(db));
  // Someone else's shop: refused.
  await assertFails(claim(as('bob')));
});

test('account deletion: users remove their own data only', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, 'users/alice'), { email: 'a@x.pk', shopId: 's1' });
    await setDoc(doc(d, 'shoppers/hana'), { name: 'Hana', coins: 5 });
    await setDoc(doc(d, 'storefronts/s1'), { ownerUid: 'alice', shopId: 's1', published: true, adminHidden: false });
  });
  await assertFails(deleteDoc(doc(as('bob'), 'users/alice')));
  await assertFails(deleteDoc(doc(as('bob'), 'shops/s1')));
  await assertFails(deleteDoc(doc(as('alice'), 'shoppers/hana')));
  await assertSucceeds(deleteDoc(doc(as('alice'), 'storefronts/s1')));
  await assertSucceeds(deleteDoc(doc(as('alice'), 'shops/s1')));
  await assertSucceeds(deleteDoc(doc(as('alice'), 'users/alice')));
  await assertSucceeds(deleteDoc(doc(as('hana'), 'shoppers/hana')));
});
