class ForumPoll {
  final String question;
  final List<String> options;
  final Map<String, int> votes; // optionIndex string '0', '1' -> vote count
  final List<String> voterUids;
  final Map<String, int> userVotes; // uid -> optionIndex

  const ForumPoll({
    required this.question,
    required this.options,
    this.votes = const {},
    this.voterUids = const [],
    this.userVotes = const {},
  });

  int get totalVotes => votes.values.fold(0, (sum, v) => sum + v);

  Map<String, dynamic> toMap() {
    return {
      'question': question,
      'options': options,
      'votes': votes,
      'voterUids': voterUids,
      'userVotes': userVotes,
    };
  }

  factory ForumPoll.fromMap(Map<String, dynamic> map) {
    return ForumPoll(
      question: map['question']?.toString() ?? '',
      options: List<String>.from(map['options'] ?? []),
      votes: (map['votes'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num).toInt()),
          ) ??
          {},
      voterUids: List<String>.from(map['voterUids'] ?? []),
      userVotes: (map['userVotes'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num).toInt()),
          ) ??
          {},
    );
  }

  ForumPoll copyWith({
    String? question,
    List<String>? options,
    Map<String, int>? votes,
    List<String>? voterUids,
    Map<String, int>? userVotes,
  }) {
    return ForumPoll(
      question: question ?? this.question,
      options: options ?? this.options,
      votes: votes ?? this.votes,
      voterUids: voterUids ?? this.voterUids,
      userVotes: userVotes ?? this.userVotes,
    );
  }
}
