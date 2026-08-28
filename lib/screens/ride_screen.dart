import 'package:flutter/material.dart';

/// The cycle lifecycle is intentionally owned by CycleScreen. This route is a
/// read-only safety notice rather than a second path that could end a ride
/// without physically locking a bicycle.
class RideScreen extends StatelessWidget {
  const RideScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ride safety')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text('Use the Cycle tab to return your bicycle. A ride can only end after a destination stand confirms its physical lock.', textAlign: TextAlign.center),
          ),
        ),
      );
}
