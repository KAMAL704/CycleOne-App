import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _controller = TextEditingController();
  bool _loading = false;

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final message = _controller.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please write your feedback first.')));
      return;
    }
    if (message.length > 2000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Feedback must be 2,000 characters or fewer.')));
      return;
    }
    setState(() => _loading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw const AuthException('Please sign in again.');
      await Supabase.instance.client.from('feedback').insert({'user_id': user.id, 'message': message});
      _controller.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks — your feedback was sent.')));
    } on PostgrestException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send feedback: ${error.message}')));
    } on AuthException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Feedback')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text('Help us improve CycleOne', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Tell the campus mobility team what worked and what could be better.'),
          const SizedBox(height: 20),
          TextField(controller: _controller, maxLines: 8, maxLength: 2000, decoration: const InputDecoration(labelText: 'Your feedback', hintText: 'Share your experience…')),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _loading ? null : _submit, icon: _loading ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send), label: Text(_loading ? 'Sending…' : 'Send feedback')),
        ]),
      );
}
