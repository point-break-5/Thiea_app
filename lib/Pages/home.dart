import 'package:flutter/material.dart';
import 'package:myapp/Pages/page2.dart';

class PageOne extends StatefulWidget {
  const PageOne({super.key});

  @override
  _PageOneState createState() => _PageOneState();
}

class _PageOneState extends State<PageOne> with SingleTickerProviderStateMixin {
  late AnimationController _imageAnimationController;

  @override
  void initState() {
    super.initState();
    _imageAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _imageAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _imageAnimationController.forward().then((value) {
          Navigator.of(context).push(_createRoute());
          _imageAnimationController
              .reset(); // Reset the animation after navigation
        });
      },
      child: Scaffold(
        backgroundColor: const Color.fromARGB(255, 178, 155, 247),
        appBar: AppBar(
          title: const Text(
            'Random App',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          centerTitle: true,
          backgroundColor: const Color.fromARGB(255, 40, 15, 65),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _imageAnimationController,
                builder: (context, child) {
                  return RotationTransition(
                    turns: Tween<double>(begin: 0, end: 1).animate(
                      CurvedAnimation(
                        parent: _imageAnimationController,
                        curve: Curves.easeInOut,
                      ),
                    ),
                    child: Image.asset(
                      'assets/logo.png',
                      width: 300,
                      height: 300,
                    ),
                  );
                },
              ),
              const SizedBox(height: 20), // Add some space
            ],
          ),
        ),
      ),
    );
  }
}

// Function to create a custom route with animation
Route _createRoute() {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => const PageTwo(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset.zero;
      const end = Offset(0.0, -1.0);
      const curve = Curves.easeInOut;

      var slideOutTween =
          Tween<Offset>(begin: begin, end: end).chain(CurveTween(curve: curve));
      var slideInTween =
          Tween<Offset>(begin: const Offset(0.0, 1.0), end: Offset.zero)
              .chain(CurveTween(curve: curve));

      var slideOutAnimation = animation.drive(slideOutTween);
      var slideInAnimation = animation.drive(slideInTween);

      return Stack(
        children: [
          SlideTransition(
            position: slideOutAnimation,
            child: child,
          ),
          SlideTransition(
            position: slideInAnimation,
            child: const PageTwo(),
          ),
        ],
      );
    },
  );
}
