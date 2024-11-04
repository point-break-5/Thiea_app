import './CommonHeader.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      routes: {
        '/homeScreen': (context) => const HomeScreen(),
        '/homeScreen/aboutUs': (context) => AboutUs(),
        '/authWrapper': (context) => const AuthWrapper(),
        '/authWrapper/logIn': (context) => const Login(),
        '/authWrapper/signUp': (context) => const Signup(),
      },


      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),

      home: const AuthWrapper(),
    );
  }
}

