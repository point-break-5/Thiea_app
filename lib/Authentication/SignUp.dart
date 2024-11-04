import '../CommonHeader.dart';

class Signup extends StatefulWidget {
  const Signup({super.key});

  // final Function toggleView;

  // const Signup({super.key, required this.toggleView});

  @override
  State<Signup> createState() => _SignupState();
}

class _SignupState extends State<Signup> {
  bool _obs_text_pass = true;
  bool _obs_text_conf_pass = true;

  String _userName = '';
  String _email = ' ';
  String _password = '';
  String _confirmedPassword = '';

  // Add the decoration method
  InputDecoration decoration(
      String hint, IconData icon, Function()? suffixAction) {
    return InputDecoration(
      hintText: hint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      fillColor: Colors.grey[200],
      filled: true,
      prefixIcon: Icon(icon),
      // Only add suffix icon if action is provided
      suffixIcon: suffixAction != null
          ? GestureDetector(
              onTap: suffixAction,
              child: const Icon(Icons.clear),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
                'assets/images/authentication_screen_background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            height: MediaQuery.of(context).size.height,
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    const SizedBox(height: 53.0),
                    const Text(
                      "Sign up",
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Create your account",
                      style: TextStyle(fontSize: 15, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 10.0)
                  ],
                ),
                Column(
                  children: [
                    TextField(
                      onChanged: (val) => setState(() {
                        _userName = val;
                      }),
                      decoration: decoration("Username", Icons.person, null),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      onChanged: (val) => setState(() {
                        _email = val;
                      }),
                      decoration: decoration("Email", Icons.email, null),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      onChanged: (val) => setState(() {
                        _password = val;
                      }),
                      decoration: InputDecoration(
                        hintText: "Password",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        fillColor: Colors.grey[200],
                        filled: true,
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: GestureDetector(
                          onTap: () {
                            setState(() {
                              _obs_text_pass = !_obs_text_pass;
                            });
                          },
                          child: Icon(_obs_text_pass
                              ? Icons.visibility
                              : Icons.visibility_off),
                        ),
                      ),
                      obscureText: _obs_text_pass,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      onChanged: (val) => setState(() {
                        _confirmedPassword = val;
                      }),
                      decoration: InputDecoration(
                        hintText: "Confirm Password",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        fillColor: Colors.grey[200],
                        filled: true,
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: GestureDetector(
                          onTap: () {
                            setState(() {
                              _obs_text_conf_pass = !_obs_text_conf_pass;
                            });
                          },
                          child: Icon(_obs_text_conf_pass
                              ? Icons.visibility
                              : Icons.visibility_off),
                        ),
                      ),
                      obscureText: _obs_text_conf_pass,
                    ),
                  ],
                ),
                Container(
                  height: 60,
                  padding: const EdgeInsets.only(top: 3, left: 3),
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.amber,
                    ),
                    child: const Text(
                      "Sign Up",
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                const Center(
                  child: Text(
                    'Or',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ),
                Container(
                  height: 45,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: Colors.purple,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ],
                  ),
                  child: TextButton(
                    onPressed: () {},
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          height: 33.0,
                          width: 33.0,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            image: DecorationImage(
                              image:
                                  AssetImage('assets/images/google_logo.png'),
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          "Sign up with google",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account?',
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacementNamed(
                            context, '/authWrapper/logIn');
                      },
                      child: const Text(
                        'Log In',
                        style: TextStyle(
                          color: Colors.amber,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
