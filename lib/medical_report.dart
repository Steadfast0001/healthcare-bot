class MedicalReport {
  final ReportMetadata reportMetadata;
  final PatientSummary patientSummary;
  final ClinicalVitals clinicalVitals;
  final HistoryOfPresentIllness historyOfPresentIllness;
  final AssessmentAndFindings assessmentAndFindings;
  final PlanAndRecommendations planAndRecommendations;
  final List<String> redFlags;

  MedicalReport({
    required this.reportMetadata,
    required this.patientSummary,
    required this.clinicalVitals,
    required this.historyOfPresentIllness,
    required this.assessmentAndFindings,
    required this.planAndRecommendations,
    required this.redFlags,
  });

  factory MedicalReport.fromJson(Map<String, dynamic> json) {
    return MedicalReport(
      reportMetadata: ReportMetadata.fromJson(json['report_metadata'] ?? {}),
      patientSummary: PatientSummary.fromJson(json['patient_summary'] ?? {}),
      clinicalVitals: ClinicalVitals.fromJson(json['clinical_vitals'] ?? {}),
      historyOfPresentIllness: HistoryOfPresentIllness.fromJson(json['history_of_present_illness'] ?? {}),
      assessmentAndFindings: AssessmentAndFindings.fromJson(json['assessment_and_findings'] ?? {}),
      planAndRecommendations: PlanAndRecommendations.fromJson(json['plan_and_recommendations'] ?? {}),
      redFlags: (json['red_flags'] as List?)?.map((item) => item.toString()).toList() ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'report_metadata': reportMetadata.toJson(),
    'patient_summary': patientSummary.toJson(),
    'clinical_vitals': clinicalVitals.toJson(),
    'history_of_present_illness': historyOfPresentIllness.toJson(),
    'assessment_and_findings': assessmentAndFindings.toJson(),
    'plan_and_recommendations': planAndRecommendations.toJson(),
    'red_flags': redFlags,
  };
}

class ReportMetadata {
  final String reportId;
  final String timestamp;
  final String confidentialityLevel;

  ReportMetadata({
    required this.reportId,
    required this.timestamp,
    required this.confidentialityLevel,
  });

  factory ReportMetadata.fromJson(Map<String, dynamic> json) {
    return ReportMetadata(
      reportId: json['report_id']?.toString() ?? '',
      timestamp: json['timestamp']?.toString() ?? '',
      confidentialityLevel: json['confidentiality_level']?.toString() ?? 'RESTRICTED MEDICAL RECORD',
    );
  }

  Map<String, dynamic> toJson() => {
    'report_id': reportId,
    'timestamp': timestamp,
    'confidentiality_level': confidentialityLevel,
  };
}

class PatientSummary {
  final int? age;
  final String? gender;
  final String? chiefComplaint;

  PatientSummary({this.age, this.gender, this.chiefComplaint});

  factory PatientSummary.fromJson(Map<String, dynamic> json) {
    return PatientSummary(
      age: json['age'] is int ? json['age'] : int.tryParse(json['age']?.toString() ?? ''),
      gender: json['gender']?.toString(),
      chiefComplaint: json['chief_complaint']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'age': age,
    'gender': gender,
    'chief_complaint': chiefComplaint,
  };
}

class ClinicalVitals {
  final String? bloodPressure;
  final String? heartRate;
  final String? temperature;
  final String? spO2;

  ClinicalVitals({this.bloodPressure, this.heartRate, this.temperature, this.spO2});

  factory ClinicalVitals.fromJson(Map<String, dynamic> json) {
    return ClinicalVitals(
      bloodPressure: json['blood_pressure']?.toString(),
      heartRate: json['heart_rate']?.toString(),
      temperature: json['temperature']?.toString(),
      spO2: json['spO2']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'blood_pressure': bloodPressure,
    'heart_rate': heartRate,
    'temperature': temperature,
    'spO2': spO2,
  };
}

class HistoryOfPresentIllness {
  final String? onset;
  final String? duration;
  final String? severity;
  final String? description;

  HistoryOfPresentIllness({this.onset, this.duration, this.severity, this.description});

  factory HistoryOfPresentIllness.fromJson(Map<String, dynamic> json) {
    return HistoryOfPresentIllness(
      onset: json['onset']?.toString(),
      duration: json['duration']?.toString(),
      severity: json['severity']?.toString(),
      description: json['description']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'onset': onset,
    'duration': duration,
    'severity': severity,
    'description': description,
  };
}

class AssessmentAndFindings {
  final String? physicalExamination;
  final String? primaryDiagnosis;
  final List<String> differentialDiagnoses;
  final String? icd10Code;

  AssessmentAndFindings({
    this.physicalExamination,
    this.primaryDiagnosis,
    required this.differentialDiagnoses,
    this.icd10Code,
  });

  factory AssessmentAndFindings.fromJson(Map<String, dynamic> json) {
    return AssessmentAndFindings(
      physicalExamination: json['physical_examination']?.toString(),
      primaryDiagnosis: json['primary_diagnosis']?.toString(),
      differentialDiagnoses: (json['differential_diagnoses'] as List?)?.map((item) => item.toString()).toList() ?? const [],
      icd10Code: json['icd_10_code']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'physical_examination': physicalExamination,
    'primary_diagnosis': primaryDiagnosis,
    'differential_diagnoses': differentialDiagnoses,
    'icd_10_code': icd10Code,
  };
}

class PlanAndRecommendations {
  final List<Medication> medications;
  final List<String> diagnosticTestsOrdered;
  final List<String> lifestyleAdvice;
  final String? followUp;

  PlanAndRecommendations({
    required this.medications,
    required this.diagnosticTestsOrdered,
    required this.lifestyleAdvice,
    this.followUp,
  });

  factory PlanAndRecommendations.fromJson(Map<String, dynamic> json) {
    return PlanAndRecommendations(
      medications: (json['medications'] as List?)?.map((item) => Medication.fromJson(item)).toList() ?? const [],
      diagnosticTestsOrdered: (json['diagnostic_tests_ordered'] as List?)?.map((item) => item.toString()).toList() ?? const [],
      lifestyleAdvice: (json['lifestyle_advice'] as List?)?.map((item) => item.toString()).toList() ?? const [],
      followUp: json['follow_up']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'medications': medications.map((m) => m.toJson()).toList(),
    'diagnostic_tests_ordered': diagnosticTestsOrdered,
    'lifestyle_advice': lifestyleAdvice,
    'follow_up': followUp,
  };
}

class Medication {
  final String? name;
  final String? dosage;
  final String? frequency;
  final String? duration;

  Medication({this.name, this.dosage, this.frequency, this.duration});

  factory Medication.fromJson(Map<String, dynamic> json) {
    return Medication(
      name: json['name']?.toString(),
      dosage: json['dosage']?.toString(),
      frequency: json['frequency']?.toString(),
      duration: json['duration']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'dosage': dosage,
    'frequency': frequency,
    'duration': duration,
  };
}
