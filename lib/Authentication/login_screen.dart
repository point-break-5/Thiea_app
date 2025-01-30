import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../auth_controller.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/sharedAlbums/shared_albums_page.dart';

int number_of_photos = 0;
int number_of_videos = 0;
int number_of_albums = 0;

class ProfileButton extends StatelessWidget {
  final AuthController authController = Get.find<AuthController>();


  int photos;
  int videos;
  int albums;

  ProfileButton({super.key, this.photos = 0, this.videos = 0, this.albums = 0}) {
    number_of_photos = photos;
    number_of_videos = videos;
    number_of_albums = albums;
  }


  void _showModal(BuildContext context) {
    final user = authController.user.value;
    if (user != null) {
      // Show profile modal if logged in
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => ProfileModal(
          user: user,
          onLogout: () async {
            await authController.logout();
            Navigator.pop(context); // Close profile modal
          },
        ),
      );
    } else {
      // Show auth modal if not logged in
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => const AuthScreen(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsets.zero,
      icon: Obx(() {
        final user = authController.user.value;
        if (user?.photoURL != null) {
          return CircleAvatar(
            backgroundImage: NetworkImage(user!.photoURL!),
            radius: 10,
          );
        }
        return const Icon(Icons.account_circle_rounded, size: 20);
      }),
      color: Colors.white,
      onPressed: () => _showModal(context),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authController = Get.find<AuthController>();
  bool _isLogin = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      Get.snackbar(
        'Error',
        'Please fill in all fields',
        backgroundColor: Colors.red.withOpacity(0.3),
        colorText: Colors.white,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await _authController.login(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );
      } else {
        await _authController.signUp(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );
      }
      if (mounted) {
        Navigator.of(context).pop(); // Close auth modal
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        e.toString(),
        backgroundColor: Colors.red.withOpacity(0.3),
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);

    try {
      final userCred = await _authController.signInWithGoogle();
      if (userCred != null && mounted) {
        Navigator.of(context).pop(); // Close auth modal
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        e.toString(),
        backgroundColor: Colors.red.withOpacity(0.3),
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.person,
                                size: 40, color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _isLogin ? 'Login' : 'Sign Up',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildAuthFields(),
                          const SizedBox(height: 24),
                          _buildAuthButton(),
                          const SizedBox(height: 16),
                          _buildGoogleSignInButton(),
                          const SizedBox(height: 16),
                          _buildToggleButton(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ... keep existing _buildAuthFields and _buildAuthButton methods ...

  // Widget _buildGoogleSignInButton() {
  //   return ElevatedButton(
  //     onPressed: _isLoading ? null : _handleGoogleSignIn,
  //     style: ElevatedButton.styleFrom(
  //       backgroundColor: Colors.white,
  //       minimumSize: const Size(double.infinity, 50),
  //       shape: RoundedRectangleBorder(
  //         borderRadius: BorderRadius.circular(8),
  //       ),
  //     ),
  //     child: _isLoading
  //         ? const SizedBox(
  //             height: 20,
  //             width: 20,
  //             child: CircularProgressIndicator(
  //               strokeWidth: 2,
  //             ),
  //           )
  //         : Row(
  //             mainAxisAlignment: MainAxisAlignment.center,
  //             children: [
  //               Image.network(
  //                 'https://upload.wikimedia.org/wikipedia/commons/5/53/Google_%22G%22_Logo.svg',
  //                 height: 24,
  //               ),
  //               const SizedBox(width: 12),
  //               Text(
  //                 'Continue with Google',
  //                 style: TextStyle(
  //                   fontSize: 16,
  //                   color: Colors.grey[800],
  //                 ),
  //               ),
  //             ],
  //           ),
  //   );
  // }

  // ... keep existing _buildToggleButton method ...
  Widget _buildAuthFields() {
    return Column(
      children: [
        TextField(
          controller: _emailController,
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.emailAddress,
          enabled: !_isLoading,
          decoration: InputDecoration(
            labelText: 'Email',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.white),
              borderRadius: BorderRadius.circular(8),
            ),
            fillColor: Colors.white.withOpacity(0.1),
            filled: true,
            prefixIcon: Icon(Icons.email, color: Colors.white.withOpacity(0.7)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          style: const TextStyle(color: Colors.white),
          obscureText: true,
          enabled: !_isLoading,
          decoration: InputDecoration(
            labelText: 'Password',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.white),
              borderRadius: BorderRadius.circular(8),
            ),
            fillColor: Colors.white.withOpacity(0.1),
            filled: true,
            prefixIcon: Icon(Icons.lock, color: Colors.white.withOpacity(0.7)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildAuthButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _handleAuth,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.withOpacity(0.7),
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      child: _isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              _isLogin ? 'Login' : 'Sign Up',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }

  Widget _buildGoogleSignInButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleGoogleSignIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Google Icon
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    // child: Image.network(
                    //   'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                    //   height: 18,
                    //   width: 18,
                    // ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildToggleButton() {
    return Column(
      children: [
        const Row(
          children: [
            Expanded(
              child: Divider(color: Colors.white30),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'OR',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Divider(color: Colors.white30),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _isLogin
                  ? 'Don\'t have an account? '
                  : 'Already have an account? ',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _isLogin = !_isLogin;
                        _emailController.clear();
                        _passwordController.clear();
                      });
                    },
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _isLogin ? 'Sign Up' : 'Login',
                style: TextStyle(
                  color: Colors.white.withOpacity(_isLoading ? 0.5 : 1.0),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        if (_isLogin) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isLoading
                ? null
                : () {
                    // TODO: Implement forgot password functionality
                    // You can add your forgot password logic here
                  },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Forgot Password?',
              style: TextStyle(
                color: Colors.white.withOpacity(_isLoading ? 0.5 : 1.0),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class ProfileModal extends StatelessWidget {
  final User user;
  final VoidCallback onLogout;

  const ProfileModal({
    Key? key,
    required this.user,
    required this.onLogout,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Profile Image
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: ClipOval(
                    child: user.photoURL != null
                        ? Image.network(
                            user.photoURL!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _buildDefaultAvatar(),
                          )
                        : _buildDefaultAvatar(),
                  ),
                ),
                const SizedBox(height: 16),

                // User Name
                Text(
                  user.displayName ?? 'Gallery User',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // Email
                Text(
                  user.email ?? '',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),

                // Stats Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatItem('Photos', '$number_of_photos'),
                    _buildStatItem('Videos', '$number_of_videos'),
                    _buildStatItem('Albums', '$number_of_albums'),
                  ],
                ),
                const SizedBox(height: 24),

                // Logout Button
                ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      barrierDismissible: true,
                      builder: (context) => SharedLibraryScreen(
                        userId: user.uid,  // Pass the Firebase UID here
                      )
                    );
                  },
                  icon: const Icon(Icons.people, size: 18, color: Colors.white),
                  label: const Text('Shared Albums', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    minimumSize: const Size(double.infinity, 45),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Logout Button
                ElevatedButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout, size: 18, color: Colors.white,),
                  label: const Text('Logout', style: TextStyle(color: Colors.white),),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.7),
                    minimumSize: const Size(double.infinity, 45),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      color: Colors.grey.shade300,
      child: Icon(
        Icons.person,
        size: 40,
        color: Colors.grey.shade700,
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
