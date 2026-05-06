import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'main.dart'; // AppColors
import 'supabase_handler.dart';

class RegistrationForm extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onSuccess;
  final Patient? editPatient;

  const RegistrationForm({
    super.key,
    required this.onCancel,
    required this.onSuccess,
    this.editPatient,
  });

  @override
  State<RegistrationForm> createState() => _RegistrationFormState();
}

class _RegistrationFormState extends State<RegistrationForm> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  // Patient Details Controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();
  final _addressController = TextEditingController();
  final _dobController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  
  // Multi-Payment State
  List<Map<String, dynamic>> _paymentEntries = [
    {'amountController': TextEditingController(text: '0'), 'mode': 'cash'}
  ];
  final _bpController = TextEditingController();
  final _pulseController = TextEditingController();
  final _weightController = TextEditingController();
  final _spo2Controller = TextEditingController();
  final _sugarController = TextEditingController();
  final _referringDoctorController = TextEditingController();

  String _selectedTitle = '.';
  String _selectedGender = 'male';
  String _selectedAgeUnit = 'year';
  String _selectedHospital = 'Cigma Clinic';
  DateTime? _selectedDob;

  String _selectedVisitType = 'OPD';
  String _selectedVisitCategory = 'First Visit';
  int? _selectedDoctorId;

  List<Map<String, dynamic>> _doctors = [];
  
  // Search and Workflow State
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  Map<String, dynamic>? _selectedPatient;
  bool _isNewPatient = false;

  final List<String> _titles = [".", "MR", "MRS", "MAST", "BABA", "MISS", "MS", "BABY", "SMT", "BABY OF", "DR"];
  final List<String> _hospitals = ["Cigma Clinic", "Rehmania Hospital", "Jeevdani Hospital", "Dausup Hospital"];

  @override
  void initState() {
    super.initState();
    _fetchDoctors();
    _discountController.addListener(() => setState(() {}));
    _searchController.addListener(_onSearchChanged);
    _setupPaymentListeners();

    if (widget.editPatient != null) {
      _prefillEditData();
    }
  }

  void _prefillEditData() {
    final p = widget.editPatient!;
    final pd = p.fullData['patient_detail'] ?? {};
    
    _nameController.text = p.name;
    _phoneController.text = p.phone == 'N/A' ? '' : p.phone;
    _ageController.text = (pd['age'] ?? '').toString();
    _selectedAgeUnit = (pd['age_unit'] ?? 'year').toString().toLowerCase();
    _selectedGender = p.gender.toLowerCase();
    _addressController.text = p.address;
    _selectedTitle = pd['title'] ?? '.';
    
    if (pd['dob'] != null) {
      _selectedDob = DateTime.tryParse(pd['dob']);
      if (_selectedDob != null) {
        _dobController.text = DateFormat('yyyy-MM-dd').format(_selectedDob!);
      }
    }

    _selectedHospital = p.fullData['hospital_name'] ?? 'Cigma Clinic';
    _selectedVisitType = p.fullData['visit_type'] ?? 'OPD';
    _selectedVisitCategory = p.fullData['visit_category'] ?? 'First Visit';
    _selectedDoctorId = p.fullData['treating_doctor_id'];
    _referringDoctorController.text = p.fullData['referring_doctor_name'] ?? '';
    _discountController.text = (p.fullData['discount_amount'] ?? 0).toString();
    _bpController.text = p.fullData['bp'] ?? '';
    _pulseController.text = (p.fullData['pulse'] ?? '').toString();
    _weightController.text = (p.fullData['weight'] ?? '').toString();
    _spo2Controller.text = p.fullData['spo2'] ?? '';
    _sugarController.text = p.fullData['sugar'] ?? '';

    // Payments
    final payments = p.fullData['payment_entries'] as List?;
    if (payments != null && payments.isNotEmpty) {
      _paymentEntries.clear();
      for (var pay in payments) {
        final ctrl = TextEditingController(text: (pay['amount'] ?? 0).toString());
        ctrl.addListener(() => setState(() {}));
        _paymentEntries.add({
          'amountController': ctrl,
          'mode': pay['paymentMode'] ?? 'cash',
        });
      }
    }
  }

  void _setupPaymentListeners() {
    for (var entry in _paymentEntries) {
      entry['amountController'].addListener(() => setState(() {}));
    }
  }

  void _addPaymentEntry() {
    setState(() {
      final controller = TextEditingController(text: '0');
      controller.addListener(() => setState(() {}));
      _paymentEntries.add({'amountController': controller, 'mode': 'cash'});
    });
  }

  void _removePaymentEntry(int index) {
    if (_paymentEntries.length > 1) {
      setState(() {
        _paymentEntries[index]['amountController'].dispose();
        _paymentEntries.removeAt(index);
      });
    }
  }

  Timer? _searchDebounce;
  void _onSearchChanged() {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(_searchController.text.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    try {
      // name and uhid are text, so ilike works. 
      // number is bigint, so we can only use eq unless we cast it on the server.
      String orFilter = 'name.ilike.%$query%,uhid.ilike.%$query%';
      
      // If query is a number, try exact match on phone number
      if (RegExp(r'^\d+$').hasMatch(query)) {
        orFilter += ',number.eq.$query';
      }

      final response = await SupabaseHandler.client
          .from('patient_detail')
          .select()
          .or(orFilter)
          .limit(10);

      if (mounted) {
        setState(() {
          _searchResults = List<Map<String, dynamic>>.from(response);
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint("Search error: $e");
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _selectExistingPatient(Map<String, dynamic> patient) {
    setState(() {
      _selectedPatient = patient;
      _isNewPatient = false;
      
      // Pre-fill controllers
      _nameController.text = patient['name'] ?? '';
      _phoneController.text = (patient['number'] ?? '').toString();
      _ageController.text = (patient['age'] ?? '').toString();
      _selectedAgeUnit = (patient['age_unit'] ?? 'year').toString().toLowerCase();
      if (_selectedAgeUnit == 'y') _selectedAgeUnit = 'year';
      if (_selectedAgeUnit == 'm') _selectedAgeUnit = 'month';
      if (_selectedAgeUnit == 'd') _selectedAgeUnit = 'day';
      _selectedGender = (patient['gender'] ?? 'male').toString().toLowerCase();
      _addressController.text = patient['address'] ?? '';
      _selectedTitle = patient['title'] ?? '.';
      if (patient['dob'] != null) {
        _selectedDob = DateTime.tryParse(patient['dob']);
        _dobController.text = DateFormat('yyyy-MM-dd').format(_selectedDob!);
      }
    });
  }

  void _startNewPatientRegistration() {
    setState(() {
      _isNewPatient = true;
      _selectedPatient = null;
      _nameController.text = _searchController.text.trim().toUpperCase();
      // Clear others
      _phoneController.clear();
      _ageController.clear();
      _addressController.clear();
      _dobController.clear();
    });
  }

  @override
  void dispose() {
    _discountController.dispose();
    _referringDoctorController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    for (var entry in _paymentEntries) {
      entry['amountController'].dispose();
    }
    super.dispose();
  }

  Future<void> _fetchDoctors() async {
    try {
      // Fetch from config_data table as per web app logic
      final response = await SupabaseHandler.client
          .from('config_data')
          .select('data')
          .eq('data_heading', 'opd_doctor_data')
          .maybeSingle();

      if (response != null && response['data'] != null) {
        setState(() {
          _doctors = List<Map<String, dynamic>>.from(response['data']);
          if (_doctors.isNotEmpty) {
            _selectedDoctorId = _doctors[0]['id'];
          }
        });
      } else {
        // Fallback to opd_datasets if config_data is empty
        final dsResponse = await SupabaseHandler.client
            .from('opd_datasets')
            .select()
            .eq('dataname', 'treating_doctors')
            .maybeSingle();
        if (dsResponse != null && dsResponse['datajson'] != null) {
          setState(() {
            _doctors = List<Map<String, dynamic>>.from(dsResponse['datajson']);
            if (_doctors.isNotEmpty) {
              _selectedDoctorId = _doctors[0]['id'];
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching treating doctors: $e");
    }
  }

  void _onTitleChanged(String? title) {
    if (title == null) return;
    setState(() {
      _selectedTitle = title;
      final male = { "MR", "MAST", "BABA" };
      final female = { "MRS", "MISS", "MS", "SMT", "BABY" };
      if (male.contains(title)) {
        _selectedGender = 'male';
      } else if (female.contains(title)) {
        _selectedGender = 'female';
      }
    });
  }

  double _calculateTotalFees() {
    if (_selectedDoctorId == null || _doctors.isEmpty) return 0;
    final doctor = _doctors.firstWhere((d) => d['id'] == _selectedDoctorId, orElse: () => {});
    if (doctor.isEmpty) return 0;

    if (_selectedVisitCategory == 'Follow Up') {
      return (doctor['follow_up_fee'] ?? 0).toDouble();
    } else {
      return (doctor['first_visit_fee'] ?? 0).toDouble();
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? DateTime.now().subtract(const Duration(days: 365 * 25)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDob) {
      setState(() {
        _selectedDob = picked;
        _dobController.text = DateFormat('yyyy-MM-dd').format(picked);
        // Calculate age
        final now = DateTime.now();
        int age = now.year - picked.year;
        if (now.month < picked.month || (now.month == picked.month && now.day < picked.day)) {
          age--;
        }
        _ageController.text = age.toString();
        _selectedAgeUnit = 'year';
      });
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      String? uhid;

      if (widget.editPatient != null) {
        uhid = widget.editPatient!.id;
        // Update patient_detail
        await SupabaseHandler.client.from('patient_detail').update({
          'name': _nameController.text.trim().toUpperCase(),
          'number': int.tryParse(_phoneController.text.trim()),
          'age': int.tryParse(_ageController.text.trim()),
          'age_unit': _selectedAgeUnit,
          'gender': _selectedGender.toLowerCase(),
          'address': _addressController.text.trim(),
          'dob': _selectedDob?.toIso8601String(),
          'title': _selectedTitle == '.' ? null : _selectedTitle,
        }).eq('uhid', uhid);
      } else if (_selectedPatient != null) {
        uhid = _selectedPatient!['uhid'];
      } else {
        // 1. Insert into patient_detail for New Patient
        final patientData = {
          'name': _nameController.text.trim().toUpperCase(),
          'number': int.tryParse(_phoneController.text.trim()),
          'age': int.tryParse(_ageController.text.trim()),
          'age_unit': _selectedAgeUnit,
          'gender': _selectedGender.toLowerCase(),
          'address': _addressController.text.trim(),
          'dob': _selectedDob?.toIso8601String(),
          'title': _selectedTitle == '.' ? null : _selectedTitle,
        };

        final patientResponse = await SupabaseHandler.client
            .from('patient_detail')
            .insert(patientData)
            .select('uhid')
            .single();

        uhid = patientResponse['uhid'];
      }

      double totalPaid = 0;
      List<Map<String, dynamic>> finalPaymentEntries = [];
      for (var entry in _paymentEntries) {
        double amt = double.tryParse(entry['amountController'].text.trim()) ?? 0.0;
        totalPaid += amt;
        finalPaymentEntries.add({
          'amount': amt,
          'paymentMode': entry['mode'],
          'time': DateTime.now().toIso8601String(),
        });
      }

      // 2. Insert into opd_registration
      final opdData = {
        'uhid': uhid,
        'hospital_name': _selectedHospital,
        'treating_doctor_id': _selectedDoctorId,
        'visit_type': _selectedVisitType,
        'visit_category': _selectedVisitCategory,
        'referring_doctor_name': _referringDoctorController.text.trim(),
        'total_fees': _calculateTotalFees(),
        'discount_amount': double.tryParse(_discountController.text.trim()) ?? 0.0,
        'amount_paid': totalPaid,
        'bp': _bpController.text.trim(),
        'pulse': int.tryParse(_pulseController.text.trim()),
        'weight': double.tryParse(_weightController.text.trim()),
        'spo2': _spo2Controller.text.trim(),
        'sugar': _sugarController.text.trim(),
        'visit_status': 'Waiting',
        'payment_entries': finalPaymentEntries,
      };

      if (widget.editPatient != null) {
        await SupabaseHandler.client.from('opd_registration').update(opdData).eq('id', widget.editPatient!.opdRegistrationId);
      } else {
        await SupabaseHandler.client.from('opd_registration').insert(opdData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.editPatient != null ? "Updated Successfully!" : "Registration Successful!"), 
            backgroundColor: AppColors.success),
        );
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isFormVisible = _selectedPatient != null || _isNewPatient || widget.editPatient != null;

    return Container(
      color: AppColors.bgBody,
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Main Content
          Expanded(
            child: isFormVisible ? _buildFullForm() : _buildSearchScreen(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchScreen() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLargeSearchBox(),
          if (_searchController.text.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildSearchResults(),
          ],
        ],
      ),
    );
  }

  Widget _buildLargeSearchBox() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        style: GoogleFonts.poppins(fontSize: 16, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: "Search / Add Patient by Name, Number, UHID...",
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary, size: 24),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 12),
          child: Text("${_searchResults.length} Results Found", 
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ),
        ..._searchResults.map((p) => _buildPatientResultItem(p)),
        const SizedBox(height: 8),
        _buildAddNewPatientItem(),
      ],
    );
  }

  Widget _buildPatientResultItem(Map<String, dynamic> p) {
    String initials = (p['name'] ?? "?")[0].toUpperCase();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        onTap: () => _selectExistingPatient(p),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.1),
          child: Text(initials, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
        ),
        title: Text("${p['name']} | ${p['gender']?.toString().substring(0, 1).toUpperCase()} | ${p['age']}${p['age_unit']}",
          style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        subtitle: Text("#${p['uhid']}  ${p['number']}",
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
      ),
    );
  }

  Widget _buildAddNewPatientItem() {
    return InkWell(
      onTap: _startNewPatientRegistration,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withOpacity(0.2), style: BorderStyle.solid),
        ),
        child: Row(
          children: [
            const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
            const SizedBox(width: 12),
            Text("Add New Patient \"${_searchController.text}\"", 
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
          ],
        ),
      ),
    );
  }

  Widget _buildFullForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildActivePatientHeader(),
            const SizedBox(height: 32),
            _sectionTitle("Patient Information"),
            const SizedBox(height: 16),
            _buildPatientInfoFields(),
            
            const SizedBox(height: 32),
            _sectionTitle("Visit Details"),
            const SizedBox(height: 16),
            _buildVisitDetailsFields(),

            const SizedBox(height: 32),
            _sectionTitle("Vitals (Initial)"),
            const SizedBox(height: 16),
            _buildVitalsFields(),

            const SizedBox(height: 40),
            _buildActionButtons(),
            const SizedBox(height: 100), // Space for bottom
          ],
        ),
      ),
    );
  }

  Widget _buildActivePatientHeader() {
    bool isNew = _isNewPatient && widget.editPatient == null;
    bool isEdit = widget.editPatient != null;
    
    String name = isEdit ? _nameController.text : (isNew ? _nameController.text : _selectedPatient!['name']);
    String sub = isEdit ? "Editing Registration: #${widget.editPatient!.id}" : (isNew ? "New Patient Registration" : "Existing Patient: #${_selectedPatient!['uhid']}");
    String initials = name.isNotEmpty ? name[0].toUpperCase() : "?";

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF6366F1)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                Text(sub, style: GoogleFonts.poppins(fontSize: 14, color: Colors.white.withOpacity(0.9))),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() { _selectedPatient = null; _isNewPatient = false; }),
            icon: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 28),
            tooltip: "Change Patient",
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_add_rounded, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("New OPD Registration", 
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text("Fill in patient and visit information", 
                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: widget.onCancel,
            icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(title.toUpperCase(), 
          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.8)),
      ],
    );
  }

  Widget _buildPatientInfoFields() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Column(
      children: [
        _responsiveRow(isMobile, [
          _buildDropdownField<String>(
            label: "Title",
            value: _selectedTitle,
            items: _titles,
            onChanged: _onTitleChanged,
          ),
          _buildTextField(_nameController, "Full Name *", "Enter patient name", icon: Icons.person_outline),
        ]),
        const SizedBox(height: 16),
        _responsiveRow(isMobile, [
          _buildTextField(_phoneController, "Phone Number", "Enter 10 digit number", icon: Icons.phone_android_outlined, keyboardType: TextInputType.phone),
          _buildDropdownField<String>(
            label: "Gender *",
            value: _selectedGender,
            items: ['male', 'female', 'other'],
            displayMapper: (v) => v[0].toUpperCase() + v.substring(1),
            onChanged: (v) => setState(() => _selectedGender = v!),
          ),
        ]),
        const SizedBox(height: 16),
        _responsiveRow(isMobile, [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildTextField(_ageController, "Age *", "Age", icon: Icons.calendar_today_outlined, keyboardType: TextInputType.number),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdownField<String>(
                  label: "Unit",
                  value: _selectedAgeUnit,
                  items: ['year', 'month', 'day'],
                  displayMapper: (v) => v[0].toUpperCase() + v.substring(1),
                  onChanged: (v) => setState(() => _selectedAgeUnit = v!),
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: () => _selectDate(context),
            child: AbsorbPointer(
              child: _buildTextField(_dobController, "Date of Birth", "Select date", icon: Icons.cake_outlined),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        _buildTextField(_addressController, "Address", "Full residential address", icon: Icons.location_on_outlined, maxLines: 2),
      ],
    );
  }

  Widget _buildVisitDetailsFields() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final totalFees = _calculateTotalFees();

    return Column(
      children: [
        _responsiveRow(isMobile, [
          _buildDropdownField<String>(
            label: "Hospital/Clinic Name *",
            value: _selectedHospital,
            items: _hospitals,
            onChanged: (v) => setState(() => _selectedHospital = v!),
          ),
          _buildDropdownField<int?>(
            label: "Treating Doctor *",
            value: _selectedDoctorId,
            items: _doctors.map((d) => d['id'] as int?).toList(),
            displayMapper: (id) {
              if (id == null) return "Select Doctor";
              final d = _doctors.firstWhere((doc) => doc['id'] == id, orElse: () => {});
              if (d.isEmpty) return "Select Doctor";
              return "${d['doctor_name']} (₹${d['first_visit_fee']}/₹${d['follow_up_fee']})";
            },
            onChanged: (v) => setState(() => _selectedDoctorId = v!),
          ),
        ]),
        const SizedBox(height: 16),
        _responsiveRow(isMobile, [
          _buildDropdownField<String>(
            label: "Visit Category *",
            value: _selectedVisitCategory,
            items: ['First Visit', 'Follow Up', 'Emergency'],
            onChanged: (v) => setState(() => _selectedVisitCategory = v!),
          ),
          _buildTextField(_referringDoctorController, "Referring Doctor", "Enter doctor name", icon: Icons.share_location_rounded),
        ]),
        const SizedBox(height: 16),
        _responsiveRow(isMobile, [
          _buildTextField(_discountController, "Discount Amount (₹)", "0", icon: Icons.discount_outlined, keyboardType: TextInputType.number),
          const SizedBox.shrink(), // Spacer for alignment
        ]),
        const SizedBox(height: 16),
        _buildPaymentEntriesList(),
        const SizedBox(height: 24),
        _buildPaymentSummary(totalFees),
      ],
    );
  }

  Widget _buildPaymentEntriesList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Payments", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            TextButton.icon(
              onPressed: _addPaymentEntry,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
              label: const Text("Add More"),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...List.generate(_paymentEntries.length, (index) => _buildPaymentEntryRow(index)),
      ],
    );
  }

  Widget _buildPaymentEntryRow(int index) {
    final entry = _paymentEntries[index];
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            flex: 2,
            child: _buildDropdownField<String>(
              label: "Mode",
              value: entry['mode'],
              items: ['cash', 'online'],
              displayMapper: (v) => v[0].toUpperCase() + v.substring(1),
              onChanged: (v) => setState(() => entry['mode'] = v!),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: _buildTextField(entry['amountController'], "Amount (₹)", "0", icon: Icons.payments_outlined, keyboardType: TextInputType.number),
          ),
          if (_paymentEntries.length > 1) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _removePaymentEntry(index),
              icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.danger),
              padding: const EdgeInsets.only(bottom: 8),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentSummary(double totalFees) {
    final discount = double.tryParse(_discountController.text) ?? 0;
    double totalPaid = 0;
    for (var entry in _paymentEntries) {
      totalPaid += double.tryParse(entry['amountController'].text) ?? 0;
    }
    final remaining = totalFees - discount - totalPaid;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: Column(
        children: [
          _summaryRow("Consultation Fee", "₹${totalFees.toStringAsFixed(2)}"),
          const Divider(height: 24),
          _summaryRow("Discount", "₹${discount.toStringAsFixed(2)}"),
          _summaryRow("Amount Paid", "₹${totalPaid.toStringAsFixed(2)}"),
          const Divider(height: 24),
          _summaryRow("Remaining Amount", "₹${remaining.toStringAsFixed(2)}", isTotal: true, 
            color: remaining > 0 ? Colors.orange : (remaining < 0 ? Colors.red : Colors.green)),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool isTotal = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 14, fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500, color: AppColors.textSecondary)),
        Text(value, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: color ?? AppColors.textPrimary)),
      ],
    );
  }

  Widget _buildVitalsFields() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Column(
      children: [
        _responsiveRow(isMobile, [
          _buildTextField(_bpController, "Blood Pressure", "120/80", icon: Icons.speed),
          _buildTextField(_pulseController, "Pulse", "BPM", icon: Icons.favorite_border, keyboardType: TextInputType.number),
          _buildTextField(_weightController, "Weight (kg)", "0.0", icon: Icons.monitor_weight_outlined, keyboardType: TextInputType.number),
        ]),
        const SizedBox(height: 16),
        _responsiveRow(isMobile, [
          _buildTextField(_spo2Controller, "SpO2 (%)", "98", icon: Icons.air),
          _buildTextField(_sugarController, "Sugar (mg/dL)", "100", icon: Icons.water_drop_outlined),
        ]),
      ],
    );
  }

  Widget _responsiveRow(bool isMobile, List<Widget> children) {
    if (isMobile) {
      return Column(
        children: children.expand((w) => [w, const SizedBox(height: 16)]).toList()..removeLast(),
      );
    }
    return Row(
      children: children.expand((w) => [Expanded(child: w), const SizedBox(width: 16)]).toList()..removeLast(),
    );
  }


  Widget _buildTextField(TextEditingController controller, String label, String hint, {IconData? icon, TextInputType keyboardType = TextInputType.text, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icon != null ? Icon(icon, size: 20, color: AppColors.textMuted) : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          validator: (v) {
            if (label.contains('*') && (v == null || v.trim().isEmpty)) return "Required";
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildDropdownField<T>({
    required String label,
    required T value,
    required List<T> items,
    required void Function(T?) onChanged,
    String Function(T)? displayMapper,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
              style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
              items: items.map((T item) {
                return DropdownMenuItem<T>(
                  value: item,
                  child: Text(displayMapper != null ? displayMapper(item) : item.toString()),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: widget.onCancel,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text("Cancel", style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _submitForm,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text("Complete Registration", style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ),
      ],
    );
  }
}
