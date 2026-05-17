/// Read-only DTO over one row of `public.pin_deletions`. RLS restricts
/// SELECT to rows where `original_created_by = auth.uid()`, so the client
/// only ever sees its own deletions.
class ServerPinDeletionDto {
  final String pinId;
  final DateTime deletedAt;

  const ServerPinDeletionDto({required this.pinId, required this.deletedAt});

  factory ServerPinDeletionDto.fromJson(Map<String, dynamic> json) {
    return ServerPinDeletionDto(
      pinId: json['pin_id'] as String,
      deletedAt: DateTime.parse(json['deleted_at'] as String),
    );
  }
}
