class PageLayoutDefinitions {
  static bool isAutoFillEnabled = true;

  static Map<String, dynamic>? getLayoutForGroup(String groupName) {
    if (groupName == 'Indoor Patient File') return indoorFileLayout;
    if (groupName == 'Daily Drug Chart') return dailyDrugChartLayout;
    return null;
  }

  static final Map<String, dynamic> indoorFileLayout = {
    'patient_name': {'x': 191.0, 'y': 740.0, 'width': 400.0},
    'age': {'x': 113.0, 'y': 823.0, 'width': 80.0},
    'sex': {'x': 215.0, 'y': 823.0, 'width': 80.0},
    'uhid': {'x': 156.0, 'y': 862.0, 'width': 200.0},
    'ipd_no': {'x': 461.0, 'y': 862.0, 'width': 180.0},
  };

  static final Map<String, dynamic> dailyDrugChartLayout = {
    'patient_name': {'x': 200.0, 'y': 200.0},
    'uhid': {'x': 200.0, 'y': 250.0},
  };
}
