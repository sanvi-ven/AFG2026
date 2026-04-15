import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../shared/widgets/app_scaffold.dart';


class MessagesPage extends StatefulWidget {
 const MessagesPage({required this.role, this.authToken, super.key});

 final String role;
 final String? authToken;

 @override
 State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
 final _titleController = TextEditingController();
 final _bodyController = TextEditingController();
 bool _isSending = false;
 String? _sendError;
 String? _sendSuccess;

 @override
 void dispose() {
   _titleController.dispose();
   _bodyController.dispose();
   super.dispose();
 }

 Future<void> _sendBroadcast() async {
   final title = _titleController.text.trim();
   final body = _bodyController.text.trim();

   if (title.isEmpty || body.isEmpty) {
     setState(() => _sendError = 'Title and message are required.');
     return;
   }

   setState(() {
     _isSending = true;
     _sendError = null;
     _sendSuccess = null;
   });

   try {
     final token = widget.authToken?.trim() ?? 'dev-owner';
     final response = await http.post(
       Uri.parse('${AppConfig.apiBaseUrl}/api/v1/notifications/broadcast'),
       headers: {
         'Content-Type': 'application/json',
         'Authorization': 'Bearer $token',
       },
       body: jsonEncode({
         'business_id': 'default-business',
         'title': title,
         'body': body,
         'target': 'ALL_CLIENTS',
       }),
     );

     if (!mounted) return;

     if (response.statusCode >= 200 && response.statusCode < 300) {
       setState(() {
         _sendSuccess = 'Announcement sent to all clients!';
         _titleController.clear();
         _bodyController.clear();
       });
       // Clear success message after 3 seconds
       Future.delayed(const Duration(seconds: 3), () {
         if (mounted) {
           setState(() => _sendSuccess = null);
         }
       });
     } else {
       final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
       final detail = errorBody['detail'] ?? 'Failed to send announcement';
       setState(() => _sendError = detail.toString());
     }
   } catch (error) {
     if (mounted) {
       setState(() => _sendError = 'Error: $error');
     }
   } finally {
     if (mounted) {
       setState(() => _isSending = false);
     }
   }
 }

 @override
 Widget build(BuildContext context) {
   final announcements = _broadcasts;
   final unreadCount = announcements.where((announcement) => !announcement.read).length;
   final isOwner = widget.role == 'owner';


   return AppScaffold(
     title: 'Announcements',
     role: widget.role,
     authToken: widget.authToken,
     selectedRoute: '/messages',
     body: ListView(
       padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
       children: [
         _HeaderBanner(isOwner: isOwner, unreadCount: unreadCount),
         const SizedBox(height: 14),
         if (isOwner) ...[
           _BroadcastComposer(
             titleController: _titleController,
             bodyController: _bodyController,
             isSending: _isSending,
             onSend: _sendBroadcast,
             error: _sendError,
             success: _sendSuccess,
           ),
           const SizedBox(height: 20),
         ],
         Row(
           children: [
             Expanded(child: _StatCard(label: 'Announcements', value: announcements.length, icon: Icons.campaign_outlined)),
             const SizedBox(width: 10),
             Expanded(child: _StatCard(label: 'Unread', value: unreadCount, icon: Icons.mark_email_unread_outlined)),
           ],
         ),
         const SizedBox(height: 16),
         Text(
           'Broadcasts',
           style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
         ),
         const SizedBox(height: 10),
         for (final announcement in announcements) ...[
           _AnnouncementCard(announcement: announcement),
           const SizedBox(height: 12),
         ],
         const SizedBox(height: 4),
         _InfoPanel(
           title: 'No Replies Enabled',
           body: isOwner
               ? 'These are one-way announcements sent to all clients. Use the broadcast composer above to send updates.'
               : 'These are one-way announcements from the business owner. Clients can read them, but cannot reply here.',
           icon: Icons.lock_outline,
         ),
       ],
     ),
   );
 }
}


class _BroadcastComposer extends StatelessWidget {
 const _BroadcastComposer({
   required this.titleController,
   required this.bodyController,
   required this.isSending,
   required this.onSend,
   this.error,
   this.success,
 });

 final TextEditingController titleController;
 final TextEditingController bodyController;
 final bool isSending;
 final VoidCallback onSend;
 final String? error;
 final String? success;

 @override
 Widget build(BuildContext context) {
   final colorScheme = Theme.of(context).colorScheme;

   return Card(
     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
     child: Padding(
       padding: const EdgeInsets.all(16),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           Text(
             'Send Announcement to All Clients',
             style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
           ),
           const SizedBox(height: 12),
           TextField(
             controller: titleController,
             enabled: !isSending,
             decoration: InputDecoration(
               labelText: 'Title',
               border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
               contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
             ),
             maxLines: 1,
           ),
           const SizedBox(height: 12),
           TextField(
             controller: bodyController,
             enabled: !isSending,
             decoration: InputDecoration(
               labelText: 'Message',
               border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
               contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
             ),
             maxLines: 4,
           ),
           const SizedBox(height: 12),
           if (error != null)
             Padding(
               padding: const EdgeInsets.only(bottom: 12),
               child: Text(
                 error!,
                 style: TextStyle(color: colorScheme.error, fontSize: 12),
               ),
             ),
           if (success != null)
             Padding(
               padding: const EdgeInsets.only(bottom: 12),
               child: Text(
                 success!,
                 style: TextStyle(color: colorScheme.primary, fontSize: 12),
               ),
             ),
           SizedBox(
             width: double.infinity,
             child: FilledButton.icon(
               onPressed: isSending ? null : onSend,
               icon: isSending
                   ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                   : const Icon(Icons.send_outlined),
               label: Text(isSending ? 'Sending...' : 'Send to All Clients'),
             ),
           ),
         ],
       ),
     ),
   );
 }
}


class _HeaderBanner extends StatelessWidget {
 const _HeaderBanner({required this.isOwner, required this.unreadCount});


 final bool isOwner;
 final int unreadCount;


 @override
 Widget build(BuildContext context) {
   final colorScheme = Theme.of(context).colorScheme;


   return Container(
     decoration: BoxDecoration(
       borderRadius: BorderRadius.circular(20),
       gradient: LinearGradient(
         begin: Alignment.topLeft,
         end: Alignment.bottomRight,
         colors: [colorScheme.primary, colorScheme.primary],
       ),
     ),
     padding: const EdgeInsets.all(18),
     child: Row(
       children: [
         Expanded(
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               Text(
                 isOwner ? 'Broadcast Announcements' : 'Owner Announcements',
                 style: Theme.of(context).textTheme.titleMedium?.copyWith(
                       color: colorScheme.onPrimary,
                       fontWeight: FontWeight.w700,
                     ),
               ),
               const SizedBox(height: 6),
               Text(
                 isOwner
                     ? 'Send updates to all clients at once. Clients receive them as read-only announcements.'
                     : 'Read the latest updates from the business owner. Replies are disabled here.',
                 style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                       color: colorScheme.onPrimary.withValues(alpha: 0.92),
                     ),
               ),
             ],
           ),
         ),
         const SizedBox(width: 12),
         CircleAvatar(
           radius: 26,
           backgroundColor: colorScheme.onPrimary.withValues(alpha: 0.16),
           child: Icon(Icons.campaign_outlined, color: colorScheme.onPrimary),
         ),
         const SizedBox(width: 10),
         Column(
           crossAxisAlignment: CrossAxisAlignment.end,
           children: [
             Text(
               '$unreadCount unread',
               style: Theme.of(context).textTheme.titleSmall?.copyWith(
                     color: colorScheme.onPrimary,
                     fontWeight: FontWeight.w700,
                   ),
             ),
             const SizedBox(height: 4),
             Text(
               'No replies',
               style: Theme.of(context).textTheme.bodySmall?.copyWith(
                     color: colorScheme.onPrimary.withValues(alpha: 0.88),
                   ),
             ),
           ],
         ),
       ],
     ),
   );
 }
}


class _StatCard extends StatelessWidget {
 const _StatCard({required this.label, required this.value, required this.icon});


 final String label;
 final int value;
 final IconData icon;


 @override
 Widget build(BuildContext context) {
   return Card(
     margin: EdgeInsets.zero,
     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
     child: Padding(
       padding: const EdgeInsets.all(12),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           Icon(icon, size: 18),
           const SizedBox(height: 10),
           Text(
             value.toString(),
             style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
           ),
           const SizedBox(height: 4),
           Text(label, style: Theme.of(context).textTheme.bodySmall),
         ],
       ),
     ),
   );
 }
}


class _AnnouncementCard extends StatelessWidget {
 const _AnnouncementCard({required this.announcement});


 final _Announcement announcement;


 @override
 Widget build(BuildContext context) {
   final colorScheme = Theme.of(context).colorScheme;


   return Card(
     margin: EdgeInsets.zero,
     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
     child: Padding(
       padding: const EdgeInsets.all(16),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           Row(
             children: [
               Container(
                 width: 46,
                 height: 46,
                 decoration: BoxDecoration(
                   color: colorScheme.primaryContainer,
                   borderRadius: BorderRadius.circular(14),
                 ),
                 child: const Icon(Icons.campaign_outlined),
               ),
               const SizedBox(width: 12),
               Expanded(
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     Row(
                       children: [
                         Expanded(
                           child: Text(
                             announcement.title,
                             style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                           ),
                         ),
                         _StatusChip(label: announcement.read ? 'Read' : 'Unread', color: announcement.read ? colorScheme.primary : colorScheme.error),
                       ],
                     ),
                     const SizedBox(height: 4),
                     Text('${announcement.sentBy} · ${announcement.timeLabel}'),
                   ],
                 ),
               ),
             ],
           ),
           const SizedBox(height: 14),
           Text(announcement.body),
           const SizedBox(height: 12),
           Row(
             children: [
               _MetaPill(icon: Icons.groups_outlined, text: announcement.audience),
               const SizedBox(width: 10),
               _MetaPill(icon: Icons.lock_outline, text: 'Read only'),
             ],
           ),
         ],
       ),
     ),
   );
 }
}


class _InfoPanel extends StatelessWidget {
 const _InfoPanel({required this.title, required this.body, required this.icon});


 final String title;
 final String body;
 final IconData icon;


 @override
 Widget build(BuildContext context) {
   return Card(
     margin: EdgeInsets.zero,
     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
     child: Padding(
       padding: const EdgeInsets.all(16),
       child: Row(
         children: [
           Icon(icon),
           const SizedBox(width: 12),
           Expanded(
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                 const SizedBox(height: 4),
                 Text(body),
               ],
             ),
           ),
         ],
       ),
     ),
   );
 }
}


class _MetaPill extends StatelessWidget {
 const _MetaPill({required this.icon, required this.text});


 final IconData icon;
 final String text;


 @override
 Widget build(BuildContext context) {
   return Container(
     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
     decoration: BoxDecoration(
       color: Theme.of(context).colorScheme.surfaceContainerHighest,
       borderRadius: BorderRadius.circular(14),
     ),
     child: Row(
       mainAxisSize: MainAxisSize.min,
       children: [
         Icon(icon, size: 16),
         const SizedBox(width: 8),
         Text(text),
       ],
     ),
   );
 }
}


class _StatusChip extends StatelessWidget {
 const _StatusChip({required this.label, required this.color});


 final String label;
 final Color color;


 @override
 Widget build(BuildContext context) {
   return Container(
     padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
     decoration: BoxDecoration(
       color: color.withValues(alpha: 0.12),
       borderRadius: BorderRadius.circular(999),
     ),
     child: Text(
       label,
       style: Theme.of(context).textTheme.labelMedium?.copyWith(
             color: color,
             fontWeight: FontWeight.w700,
           ),
     ),
   );
 }
}


class _Announcement {
 const _Announcement({
   required this.title,
   required this.body,
   required this.sentBy,
   required this.timeLabel,
   required this.audience,
   required this.read,
 });


 final String title;
 final String body;
 final String sentBy;
 final String timeLabel;
 final String audience;
 final bool read;
}


const List<_Announcement> _broadcasts = <_Announcement>[
 _Announcement(
   title: 'Spring service availability',
   body: 'New service slots have been opened for next week. Reach out through your booking link if needed.',
   sentBy: 'RP Landscaping',
   timeLabel: '3d ago',
   audience: 'All clients',
   read: false,
 ),
];
