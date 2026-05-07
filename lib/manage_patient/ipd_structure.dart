enum AddBehavior {
  singlePageOnly,
  multiPageSingle,
  multiPageSingleCustomName,
  singlePairOnly,
  multiPagePaired,
  multiPageFromList,
  singleBook,
  multiBook,
}

class GroupConfig {
  final String groupName;
  final AddBehavior behavior;
  final String? templateTag;
  final String? templateName;
  final String pageNamePrefix;

  GroupConfig({
    required this.groupName,
    required this.behavior,
    this.templateTag,
    this.templateName,
    required this.pageNamePrefix,
  });
}

final List<GroupConfig> ipdGroupStructure = [
  GroupConfig(
    groupName: 'Prescription',
    behavior: AddBehavior.multiPagePaired,
    templateTag: 'prescription_template',
    pageNamePrefix: 'Prescription',
  ),
];

GroupConfig? findGroupConfigByName(String name) {
  try {
    return ipdGroupStructure.firstWhere((c) => c.groupName == name);
  } catch (e) {
    return null;
  }
}
