// Security rules tests, run against the Firestore emulator (see package.json).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, addDoc } from 'firebase/firestore';

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
  await assertFails(deleteDoc(doc(as('alice'), 'users/alice')));
});
