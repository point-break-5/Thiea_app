import '../CommonHeader.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  // final Function toggleView;

  // const Login({super.key, required this.toggleView});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  bool showPass = false;

  late String userName;
  late String passWord;



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,

      body: Container(
        height: MediaQuery.of(context).size.height,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
                'assets/images/authentication_screen_background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Container(
          height: MediaQuery.of(context).size.height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _header(context),
              _inputField(context),
              _forgotPassword(context),
              _signup(context),
            ],
          ),
        ),
      ),
    );
  }

  _header(context) {
    return const Column(
      children: [
        Text(
          "Welcome Back",
          style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
        ),
        Text("Enter your credential to login"),
      ],
    );
  }

  _inputField(context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: (value){
            setState(() {
              userName = value;
            });
          },
          decoration: InputDecoration(
              hintText: "Username",
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none),
              fillColor: Colors.grey[200],
              filled: true,
              prefixIcon: const Icon(Icons.person)),
        ),
        const SizedBox(height: 20),
        TextField(
          onChanged: (value){
            setState(() {
              passWord = value;
            });
          },
          decoration: InputDecoration(
              hintText: "Password",
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none),
              fillColor: Colors.grey[200],
              filled: true,
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: GestureDetector(
                onTap: () {
                  setState(() {
                    showPass = !showPass;
                  });
                },
                child:
                Icon(!showPass ? Icons.visibility : Icons.visibility_off),
              )),
          obscureText: !showPass,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            // Navigator.pushNamedAndRemoveUntil(context);
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/homeScreen',
              (Route<dynamic> route) => false,
              arguments: {
                "userName" : userName,
              }
            );
          },
          style: ElevatedButton.styleFrom(
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: Colors.amber,
          ),
          child: const Text(
            "Login",
            style: TextStyle(
              fontSize: 20,
              color: Colors.black,
            ),
          ),
        )
      ],
    );
  }

  _forgotPassword(context) {
    return TextButton(
      onPressed: () {},
      child: const Text(
        "Forgot password?",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.amber,
        ),
      ),
    );
  }

  _signup(context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "Don't have an account?",
          style: TextStyle(
            color: Colors.white,
          ),
        ),
        TextButton(
            onPressed: () {
              Navigator.pushReplacementNamed(context, '/authWrapper/signUp');
            },
            child: const Text(
              "Sign Up",
              style: TextStyle(
                color: Colors.amber,
              ),
            ))
      ],
    );
  }
}

