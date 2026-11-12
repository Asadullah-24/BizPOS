import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/permissions.dart';
import '../../models/models.dart';
import '../../services/activity_log.dart';
import '../../services/auth_service.dart';
import '../common.dart';

Future<List<Role>> _roles() async {
  final rows = await Db.instance.s.q('SELECT * FROM roles WHERE deleted_at IS NULL ORDER BY is_system DESC, name COLLATE NOCASE');
  return rows.map(Role.fromRow).toList();
}

class EmployeesScreen extends StatelessWidget {
  const EmployeesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Employees')), actions: [
        IconButton(
          tooltip: tr('Roles'),
          icon: const Icon(Icons.admin_panel_settings_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RolesScreen())),
        ),
        IconButton(
          tooltip: tr('Activity log'),
          icon: const Icon(Icons.history),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivityLogScreen())),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: Text(tr('Add employee')),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeeForm())),
      ),
      body: LiveData<(List<DbRow>, List<Role>)>(
        load: () async => (
          await Db.instance.s.q('SELECT * FROM employees WHERE deleted_at IS NULL ORDER BY is_owner DESC, name COLLATE NOCASE'),
          await _roles(),
        ),
        builder: (ctx, d) {
          final roles = {for (final r in d.$2) r.id: r.name};
          return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
            for (final r in d.$1)
              Builder(builder: (context) {
                final e = Employee.fromRow(r);
                return ListTile(
                  leading: CircleAvatar(child: Text(e.name.characters.first.toUpperCase())),
                  title: Text(e.name, style: TextStyle(color: e.active ? null : Theme.of(context).disabledColor)),
                  subtitle: Text([
                    e.isOwner ? tr('Owner') : (roles[e.roleId] ?? tr('No role')),
                    if (!e.active) tr('Disabled'),
                    if (e.phone != null && e.phone!.isNotEmpty) e.phone!,
                  ].join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EmployeeForm(employee: e))),
                );
              }),
          ]);
        },
      ),
    );
  }
}

class EmployeeForm extends StatefulWidget {
  const EmployeeForm({super.key, this.employee});
  final Employee? employee;

  @override
  State<EmployeeForm> createState() => _EmployeeFormState();
}

class _EmployeeFormState extends State<EmployeeForm> {
  late final _name = TextEditingController(text: widget.employee?.name ?? '');
  late final _phone = TextEditingController(text: widget.employee?.phone ?? '');
  final _pin = TextEditingController();
  late String? _roleId = widget.employee?.roleId;
  late bool _active = widget.employee?.active ?? true;
  List<Role> _roleList = [];

  bool get _isOwner => widget.employee?.isOwner ?? false;

  @override
  void initState() {
    super.initState();
    _roles().then((r) {
      if (!mounted) return;
      setState(() {
        _roleList = r.where((x) => !x.isSystem).toList();
        _roleId ??= _roleList.where((x) => x.name == 'Cashier').firstOrNull?.id ?? _roleList.firstOrNull?.id;
      });
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return showSnack(context, tr('Enter a name.'), error: true);
    final pin = _pin.text.trim();
    final isNew = widget.employee == null;
    if (isNew && pin.isEmpty) return showSnack(context, tr('Set a PIN for the employee.'), error: true);
    if (pin.isNotEmpty) {
      if (pin.length < 4 || int.tryParse(pin) == null) return showSnack(context, tr('PIN must be at least 4 digits.'), error: true);
      if (await AuthService.pinTaken(pin, exceptId: widget.employee?.id)) {
        if (mounted) showSnack(context, tr('Another employee already uses this PIN.'), error: true);
        return;
      }
    }
    final row = <String, Object?>{
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      if (!_isOwner) 'role_id': _roleId,
      if (!_isOwner) 'active': _active ? 1 : 0,
      if (pin.isNotEmpty) ...AuthService.pinColumns(pin),
    };
    if (isNew) {
      final id = await Db.instance.s.insert('employees', row);
      await ActivityLog.add('Employee added', entity: 'employee', entityId: id, detail: _name.text.trim());
    } else {
      await Db.instance.s.update('employees', widget.employee!.id, row);
      await ActivityLog.add(pin.isNotEmpty ? 'Employee PIN changed' : 'Employee updated',
          entity: 'employee', entityId: widget.employee!.id, detail: _name.text.trim());
      if (AppState.instance.user?.id == widget.employee!.id) {
        final r = await Db.instance.s.byId('employees', widget.employee!.id);
        if (r != null) await AppState.instance.login(Employee.fromRow(r));
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Remove employee', 'Remove ${widget.employee!.name}? Their past activity stays in the log.', danger: true)) return;
    await Db.instance.s.softDelete('employees', widget.employee!.id);
    await ActivityLog.add('Employee removed', entity: 'employee', entityId: widget.employee!.id, detail: widget.employee!.name);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(widget.employee == null ? 'Add employee' : 'Edit employee')),
        actions: [if (widget.employee != null && !_isOwner) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete)],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: InputDecoration(labelText: tr('Name'))),
        const SizedBox(height: 12),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Phone'))),
        const SizedBox(height: 12),
        if (_isOwner)
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.verified_user), title: Text(tr('Owner: full access')))
        else
          DropdownButtonFormField<String>(
            value: _roleList.any((r) => r.id == _roleId) ? _roleId : null,
            decoration: InputDecoration(labelText: tr('Role')),
            items: [for (final r in _roleList) DropdownMenuItem(value: r.id, child: Text(r.name))],
            onChanged: (v) => setState(() => _roleId = v),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: InputDecoration(labelText: tr(widget.employee == null ? 'PIN (4-8 digits)' : 'New PIN (leave empty to keep)')),
        ),
        if (!_isOwner)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Can sign in')),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: Text(tr('Save'))),
      ]),
    );
  }
}

class RolesScreen extends StatelessWidget {
  const RolesScreen({super.key});

  Future<void> _edit(BuildContext context, [Role? role]) async {
    final name = TextEditingController(text: role?.name ?? '');
    final perms = {...?role?.permissions};
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => Scaffold(
            appBar: AppBar(title: Text(tr(role == null ? 'New role' : 'Edit role')), actions: [
              if (role != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await confirm(ctx, 'Delete role', 'Employees with this role will lose access until you give them another role.', danger: true)) {
                      await Db.instance.s.softDelete('roles', role.id);
                      if (ctx.mounted) Navigator.pop(ctx, false);
                    }
                  },
                ),
            ]),
            body: ListView(children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(controller: name, decoration: InputDecoration(labelText: tr('Role name'))),
              ),
              for (final e in Perm.labels.entries)
                CheckboxListTile(
                  title: Text(tr(e.value)),
                  value: perms.contains(e.key),
                  onChanged: (v) => setS(() => v == true ? perms.add(e.key) : perms.remove(e.key)),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final row = {'name': name.text.trim(), 'permissions': jsonEncode(perms.toList())};
    if (role == null) {
      await Db.instance.s.insert('roles', row);
    } else {
      await Db.instance.s.update('roles', role.id, row);
    }
    await AppState.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Roles'))),
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(context), child: const Icon(Icons.add)),
      body: LiveData<List<Role>>(
        load: _roles,
        builder: (ctx, roles) => ListView(children: [
          for (final r in roles)
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: Text(r.name),
              subtitle: Text(r.isSystem ? tr('Full access (owner)') : '${r.permissions.length} ${tr('permissions')}'),
              trailing: r.isSystem ? null : const Icon(Icons.chevron_right),
              onTap: r.isSystem ? null : () => _edit(context, r),
            ),
        ]),
      ),
    );
  }
}

class ActivityLogScreen extends StatelessWidget {
  const ActivityLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Activity log'))),
      body: LiveData<List<DbRow>>(
        load: () => Db.instance.s.q('SELECT * FROM activity_logs WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT 1000'),
        builder: (ctx, list) => list.isEmpty
            ? const EmptyState(icon: Icons.history, text: 'Nothing here yet')
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final a = list[i];
                  return ListTile(
                    dense: true,
                    title: Text(tr(a['action'] as String)),
                    subtitle: Text([
                      if ((a['detail'] ?? '') != '') a['detail'] as String,
                      '${a['employee_name'] ?? '-'} · ${Fmt.dateTime(asInt(a['created_at']))}',
                    ].join('\n')),
                  );
                },
              ),
      ),
    );
  }
}
