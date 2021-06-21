import 'package:flutter/material.dart';
import 'package:flutter_execution/flutter_execution.dart';


void main() {
  runApp(ExecutionExample());
}

class ExecutionExample extends StatefulWidget {
  const ExecutionExample({Key? key}) : super(key: key);

  @override
  _ExecutionExampleState createState() => _ExecutionExampleState();
}

class _ExecutionExampleState extends State<ExecutionExample> {
  @override
  void initState() {
    Execution.instance.initialize();
    // Execution.instance.doOnceForever(key: key, function: function)
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Execution Example',
      home: Scaffold(
        appBar: AppBar(
          title: Text('Execution example'),
        ),
        body: Column(
          children: [
            // ElevatedButton(onPressed: onPressed, child: child)
          ],
        ),
      ),
    );
  }
}
