import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DoctorSelectionDialog extends StatefulWidget {
  const DoctorSelectionDialog({super.key});

  @override
  State<DoctorSelectionDialog> createState() => _DoctorSelectionDialogState();
}

class _DoctorSelectionDialogState extends State<DoctorSelectionDialog> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isCreating = false;
  List<Map<String, dynamic>> _doctors = [];

  // Form Controllers
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchDoctors();
  }

  Future<void> _fetchDoctors() async {
    try {
      final response = await supabase
          .from('opd_datasets')
          .select()
          .eq('dataname', 'refer_doctors')
          .maybeSingle();

      if (response != null && response['datajson'] != null) {
        setState(() {
          _doctors = List<Map<String, dynamic>>.from(response['datajson']);
        });
      }
    } catch (e) {
      debugPrint("Error fetching doctors: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveNewDoctor() async {
    if (!_formKey.currentState!.validate()) return;

    final newDoctor = {
      "name": _nameController.text.trim(),
      "phone": _phoneController.text.trim(),
      "address": _addressController.text.trim(),
      "id": DateTime.now().millisecondsSinceEpoch.toString(), // Simple ID
    };

    setState(() => _isLoading = true);

    try {
      // Add to local list
      final updatedList = [..._doctors, newDoctor];

      // Update Supabase
      await supabase.from('opd_datasets').upsert({
        'dataname': 'refer_doctors',
        'datajson': updatedList,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'dataname');

      setState(() {
        _doctors = updatedList;
        _isCreating = false;
        // Clear form
        _nameController.clear();
        _phoneController.clear();
        _addressController.clear();
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_isCreating ? "Add New Doctor" : "Select Refer Doctor",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
            const Divider(),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_isCreating)
              _buildCreateForm()
            else
              _buildList(),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return SizedBox(
      height: 300,
      child: Column(
        children: [
          Expanded(
            child: _doctors.isEmpty
                ? const Center(child: Text("No doctors found. Create one."))
                : ListView.builder(
              itemCount: _doctors.length,
              itemBuilder: (context, index) {
                final doc = _doctors[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade50,
                    child: Text(doc['name'][0].toUpperCase(), style: const TextStyle(color: Colors.blue)),
                  ),
                  title: Text(doc['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(doc['phone'] ?? ''),
                  onTap: () {
                    // Return the selected doctor
                    Navigator.pop(context, doc);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () => setState(() => _isCreating = true),
            icon: const Icon(Icons.add),
            label: const Text("Create New Doctor"),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 45),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCreateForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: "Doctor Name (Required)", border: OutlineInputBorder()),
            validator: (v) => v == null || v.isEmpty ? "Name is required" : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneController,
            decoration: const InputDecoration(labelText: "Phone Number", border: OutlineInputBorder()),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _addressController,
            decoration: const InputDecoration(labelText: "Address", border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() => _isCreating = false),
                  child: const Text("Cancel"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveNewDoctor,
                  child: const Text("Save Doctor"),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}