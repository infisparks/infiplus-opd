import 'package:flutter/material.dart';
import '../../main.dart'; // Imports Patient model

// --- DATA MODELS ---

class MedicalHistoryItem {
  String name;
  bool isSelected;
  String? detail; // e.g., "3-6 Months"
  String? subDetail; // e.g., "Medication: Yes"
  List<String> tags; // e.g., ["Father", "Sister"] for Family History

  MedicalHistoryItem({required this.name, this.isSelected = false, this.detail, this.subDetail, this.tags = const []});
}

// ---------------------------------------

class MedicalHistoryTab extends StatefulWidget {
  const MedicalHistoryTab({super.key});

  @override
  State<MedicalHistoryTab> createState() => _MedicalHistoryTabState();
}

class _MedicalHistoryTabState extends State<MedicalHistoryTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // --- SCROLL CONTROL ---
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _sectionKeys = {
    0: GlobalKey(), // Problems
    1: GlobalKey(), // Allergies
    2: GlobalKey(), // Family
    3: GlobalKey(), // Lifestyle
    4: GlobalKey(), // Procedure
    5: GlobalKey(), // Risk
    6: GlobalKey(), // Other
  };

  // --- DATA ---
  final List<MedicalHistoryItem> _problems = [
    MedicalHistoryItem(name: "T2DM"), MedicalHistoryItem(name: "Hypertension"),
    MedicalHistoryItem(name: "Hypothyroidism"), MedicalHistoryItem(name: "Hyperthyroidism"),
    MedicalHistoryItem(name: "Hyperlipidemia"), MedicalHistoryItem(name: "CKD"),
    MedicalHistoryItem(name: "Obesity"), MedicalHistoryItem(name: "Weight loss"),
  ];

  final List<MedicalHistoryItem> _allergies = [
    MedicalHistoryItem(name: "Peanuts"), MedicalHistoryItem(name: "Pollen"),
    MedicalHistoryItem(name: "Shellfish"), MedicalHistoryItem(name: "Sulfa drugs"),
    MedicalHistoryItem(name: "Amoxicillin"),
  ];

  final List<MedicalHistoryItem> _familyHistory = [
    MedicalHistoryItem(name: "Hypertension"), MedicalHistoryItem(name: "Hypothyroidism"),
    MedicalHistoryItem(name: "Obesity"), MedicalHistoryItem(name: "CKD"),
  ];

  final List<MedicalHistoryItem> _lifestyle = [
    MedicalHistoryItem(name: "Smoking"), MedicalHistoryItem(name: "Drinking"),
    MedicalHistoryItem(name: "Food Habits"), MedicalHistoryItem(name: "Exercise"),
  ];

  // --- ACTIONS ---

  void _scrollToSection(int index) {
    final context = _sectionKeys[index]?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(context, curve: Curves.easeInOut);
    }
  }

  void _handleChipTap(String section, MedicalHistoryItem item) async {
    setState(() => item.isSelected = !item.isSelected);

    if (!item.isSelected) {
      // Clear details if deselected
      setState(() {
        item.detail = null;
        item.subDetail = null;
        item.tags = [];
      });
      return;
    }

    // --- POPUP LOGIC BASED ON SELECTION ---

    if (item.name == "T2DM" || item.name == "Hypertension") {
      // 1. Show Duration/Medication Dialog
      await _showProblemDetailsDialog(item);
    }
    else if (section == "Family" && (item.name == "Obesity" || item.name == "Hypertension")) {
      // 2. Show Family Member Dialog
      await _showFamilyMemberDialog(item);
    }
    else if (item.name == "Food Habits") {
      // 3. Show Food Habit Dialog
      await _showFoodHabitsDialog(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- LEFT CONTENT AREA ---
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const Divider(height: 30),

                // 1. Medical Problems
                _buildSectionContainer(0, "1. Medical Problems", [
                  const Text("Select medical problem", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: _problems.map((i) => _buildChip(i, "Problem")).toList()),
                  const SizedBox(height: 15),
                  _buildTextField("Chief complains"),
                  const SizedBox(height: 10),
                  _buildTextField("K/c/o"),
                  const SizedBox(height: 10),
                  _buildTextField("Past history"),
                ]),

                const Divider(height: 40),

                // 2. Allergies
                _buildSectionContainer(1, "2. Allergies", [
                  const Text("General & Drug Allergies", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: _allergies.map((i) => _buildChip(i, "Allergy")).toList()),
                  const SizedBox(height: 10),
                  _buildTextField("Other Allergies"),
                ]),

                const Divider(height: 40),

                // 3. Family History
                _buildSectionContainer(2, "3. Family History", [
                  const Text("What illnesses run in your family?", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: _familyHistory.map((i) => _buildChip(i, "Family")).toList()),
                ]),

                const Divider(height: 40),

                // 4. Lifestyle
                _buildSectionContainer(3, "4. Lifestyle", [
                  const Text("Lifestyle Details", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: _lifestyle.map((i) => _buildChip(i, "Lifestyle")).toList()),
                ]),

                const Divider(height: 40),

                // 5. Procedure
                _buildSectionContainer(4, "5. Procedure", [
                  const Text("Have you undergone any procedures?", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                  const SizedBox(height: 10),
                  Row(children: [
                    _buildRadioBtn("Yes"), const SizedBox(width: 10),
                    _buildRadioBtn("No"), const SizedBox(width: 10),
                    _buildRadioBtn("Don't Know"),
                  ]),
                ]),

                const SizedBox(height: 300), // Extra space for scrolling
              ],
            ),
          ),
        ),

        // --- RIGHT SIDEBAR NAVIGATION ---
        Container(
          width: 200,
          // FIX: Color moved INSIDE BoxDecoration
          decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(left: BorderSide(color: Colors.grey[300]!))
          ),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 20),
            children: [
              _buildSidebarItem("1. Medical Problems", 0),
              _buildSidebarItem("2. Allergies", 1),
              _buildSidebarItem("3. Family History", 2),
              _buildSidebarItem("4. Lifestyle", 3),
              _buildSidebarItem("5. Procedure", 4),
              _buildSidebarItem("6. Risk Factor", 5),
              _buildSidebarItem("7. Other", 6),
            ],
          ),
        ),
      ],
    );
  }

  // --- UI WIDGETS ---

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("General Medical History", style: TextStyle(fontSize: 12, color: Colors.grey)),
        Row(
          children: [
            OutlinedButton(onPressed: (){}, child: const Text("Add New Question")),
            const SizedBox(width: 8),
            ElevatedButton(
                onPressed: (){},
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                child: const Text("Save")
            ),
          ],
        )
      ],
    );
  }

  Widget _buildSectionContainer(int keyIndex, String title, List<Widget> children) {
    return Container(
      key: _sectionKeys[keyIndex],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
          const SizedBox(height: 20),
          ...children
        ],
      ),
    );
  }

  Widget _buildChip(MedicalHistoryItem item, String section) {
    bool isSelected = item.isSelected;
    // Construct label with details if present
    String label = item.name;
    if (item.detail != null) label += " (${item.detail})";
    if (item.tags.isNotEmpty) label += " (${item.tags.join(', ')})";

    return InkWell(
      onTap: () => _handleChipTap(section, item),
      child: Chip(
        label: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontSize: 12)),
        backgroundColor: isSelected ? AppColors.primary : Colors.white,
        side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey[300]!),
        deleteIcon: isSelected ? const Icon(Icons.close, size: 16, color: Colors.white) : null,
        onDeleted: isSelected ? () => _handleChipTap(section, item) : null,
      ),
    );
  }

  Widget _buildTextField(String hint) {
    return TextField(
      decoration: InputDecoration(
          labelText: hint,
          filled: true, fillColor: Colors.grey[50],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey[300]!)),
          suffixIcon: TextButton(onPressed: (){}, child: const Text("Add Notes", style: TextStyle(fontSize: 10)))
      ),
    );
  }

  Widget _buildSidebarItem(String title, int index) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      onTap: () => _scrollToSection(index),
      dense: true,
      hoverColor: Colors.blue.withOpacity(0.05),
    );
  }

  Widget _buildRadioBtn(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  // --- DIALOGS (The Logic Engine) ---

  // 1. Duration & Medication Dialog
  Future<void> _showProblemDetailsDialog(MedicalHistoryItem item) async {
    String? selectedDuration;
    String medicationStatus = "No";
    List<String> durations = ["0-3 Months", "3-6 Months", "6-12 Months", "1-2 Years", "5+ Years"];

    await showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(builder: (context, setDialogState) {
            return AlertDialog(
              title: Text("${item.name} Details"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Duration:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: durations.map((d) {
                    return ChoiceChip(
                      label: Text(d),
                      selected: selectedDuration == d,
                      onSelected: (val) => setDialogState(() => selectedDuration = d),
                    );
                  }).toList()),
                  const SizedBox(height: 20),
                  const Text("Medication?", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(children: [
                    ChoiceChip(label: const Text("Yes"), selected: medicationStatus == "Yes", onSelected: (v) => setDialogState(() => medicationStatus = "Yes")),
                    const SizedBox(width: 10),
                    ChoiceChip(label: const Text("No"), selected: medicationStatus == "No", onSelected: (v) => setDialogState(() => medicationStatus = "No")),
                  ]),
                  if (medicationStatus == "Yes")
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: TextButton.icon(
                        icon: const Icon(Icons.search),
                        label: const Text("Search Medicine"),
                        onPressed: () {
                          // Open nested search
                          Navigator.pop(context); // Close current
                          _showMedicineSearchDialog(); // Open Search
                        },
                      ),
                    )
                ],
              ),
              actions: [
                TextButton(onPressed: () {
                  setState(() {
                    item.detail = selectedDuration;
                    item.subDetail = "Meds: $medicationStatus";
                  });
                  Navigator.pop(context);
                }, child: const Text("Done"))
              ],
            );
          });
        }
    );
  }

  // 2. Medicine Search Dialog (Nested)
  Future<void> _showMedicineSearchDialog() async {
    await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text("Enter medicine name"),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const TextField(decoration: InputDecoration(hintText: "e.g. Paracetamol", prefixIcon: Icon(Icons.search))),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: ["Paarmol", "P_g_enema"].map((m) => Chip(label: Text(m), onDeleted: (){})).toList(),
                  )
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Done"))
            ],
          );
        }
    );
  }

  // 3. Family Member Dialog
  Future<void> _showFamilyMemberDialog(MedicalHistoryItem item) async {
    Set<String> members = {};
    List<String> options = ["Father", "Mother", "Spouse", "Sister", "Brother", "Aunt"];

    await showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(builder: (context, setDialogState) {
            return AlertDialog(
              title: Text("Who has ${item.name}?"),
              content: Wrap(
                spacing: 8,
                children: options.map((opt) {
                  bool isSel = members.contains(opt);
                  return FilterChip(
                    label: Text(opt),
                    selected: isSel,
                    onSelected: (val) {
                      setDialogState(() {
                        if(val) members.add(opt); else members.remove(opt);
                      });
                    },
                  );
                }).toList(),
              ),
              actions: [
                TextButton(onPressed: () {
                  setState(() {
                    item.tags = members.toList();
                  });
                  Navigator.pop(context);
                }, child: const Text("Done"))
              ],
            );
          });
        }
    );
  }

  // 4. Food Habits Dialog
  Future<void> _showFoodHabitsDialog(MedicalHistoryItem item) async {
    String? habit;
    await showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(builder: (c, s) => AlertDialog(
            title: const Text("What are your food habits?"),
            content: Wrap(spacing: 8, children: ["Veg", "Non-veg", "Eggetarian", "Keto"].map((h) =>
                ChoiceChip(label: Text(h), selected: habit == h, onSelected: (v) => s(() => habit = h))
            ).toList()),
            actions: [
              TextButton(onPressed: () {
                setState(() => item.detail = habit);
                Navigator.pop(context);
              }, child: const Text("Done"))
            ],
          ));
        }
    );
  }
}