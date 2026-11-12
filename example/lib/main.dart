import 'package:flutter/material.dart';
import 'package:do_once/do_once.dart';

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
    Execution.instance.initialize().then((_) {
      Execution.instance.doOnceForever(
        key: 'printOnce',
        function: () => print(
          '============== Print only once forever ===============',
        ),
      );
    });

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Execution Example',
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Execution example'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ElevatedButton(onPressed: onPressed, child: child)
            ElevatedButton(
              onPressed: () {
                Execution.instance.dispose();
              },
              child: Text(
                'dispose',
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (BuildContext context) => NextPage(),
                  ),
                );
              },
              child: Text(
                'Next Page',
              ),
            )
          ],
        ),
      ),
    );
  }
}

class NextPage extends StatefulWidget {
  const NextPage({Key? key}) : super(key: key);

  @override
  _NextPageState createState() => _NextPageState();
}

class _NextPageState extends State<NextPage> {
  @override
  void initState() {
    Execution.instance.doOnceOnSession(
      key: 'printonceOnSession',
      function: () async => await Future.delayed(Duration(seconds: 5)).then(
          (_) => print(
              '============= Print only once on session ===============')),
    );

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Next Page'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('This is the next Page'),
          ],
        ),
      ),
    );
  }
}
