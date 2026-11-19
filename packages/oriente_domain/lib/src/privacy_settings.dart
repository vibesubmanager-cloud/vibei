class PrivacySettings {
  const PrivacySettings({
    this.onlineVisionConsent = false,
    this.onlineChatConsent = false,
    this.speechRate = 1.0,
    this.speechVolume = 1.0,
    this.speechLanguage = 'en-US',
  });

  final bool onlineVisionConsent;
  final bool onlineChatConsent;
  final double speechRate;
  final double speechVolume;

  /// BCP-47 tag for ASR: en-US | en-GB | en-IN.
  final String speechLanguage;

  PrivacySettings copyWith({
    bool? onlineVisionConsent,
    bool? onlineChatConsent,
    double? speechRate,
    double? speechVolume,
    String? speechLanguage,
  }) {
    return PrivacySettings(
      onlineVisionConsent: onlineVisionConsent ?? this.onlineVisionConsent,
      onlineChatConsent: onlineChatConsent ?? this.onlineChatConsent,
      speechRate: speechRate ?? this.speechRate,
      speechVolume: speechVolume ?? this.speechVolume,
      speechLanguage: speechLanguage ?? this.speechLanguage,
    );
  }

  Map<String, Object?> toMap() => {
        'onlineVisionConsent': onlineVisionConsent,
        'onlineChatConsent': onlineChatConsent,
        'speechRate': speechRate,
        'speechVolume': speechVolume,
        'speechLanguage': speechLanguage,
      };

  factory PrivacySettings.fromMap(Map<Object?, Object?> map) {
    return PrivacySettings(
      onlineVisionConsent: map['onlineVisionConsent'] as bool? ?? false,
      onlineChatConsent: map['onlineChatConsent'] as bool? ?? false,
      speechRate: (map['speechRate'] as num?)?.toDouble() ?? 1.0,
      speechVolume: (map['speechVolume'] as num?)?.toDouble() ?? 1.0,
      speechLanguage: map['speechLanguage'] as String? ?? 'en-US',
    );
  }
}
