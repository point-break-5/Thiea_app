import '../CommonHeader.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: ListView(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  Colors.blue,
                  Colors.blueAccent,
                ],
              ),
            ),
            child: Container(
              child: Column(
                children: [
                  // Material(
                  //   borderRadius: BorderRadius.all(Radius.circular(50.0)),
                  //   elevation: 10,
                  //   child: Padding(
                  //     padding: const EdgeInsets.all(8.0),
                  //     child: Image.asset(
                  //       'assets/images/flutter_logo.png',
                  //       width: 60,
                  //       height: 60,
                  //     ),
                  //   ),
                  // ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Flutter',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Customtile(Icons.person, 'Profile', () => {}),
          Customtile(Icons.notifications, 'Notifications', () => {}),
          Customtile(Icons.settings, 'Settings', () => {}),
          Customtile(Icons.info, 'About Us', () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/homeScreen/aboutUs');
          }),
          Customtile(
              Icons.logout,
              'Logout',
              () => {
                    Navigator.pushNamed(context, '/authWrapper'),
                  }),
        ],
      ),
    );
  }
}

class Customtile extends StatelessWidget {
  final IconData icon;
  final String text;
  final Function onTap;

  const Customtile(this.icon, this.text, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Card(
        child: InkWell(
          splashColor: Colors.amber,
          onTap: () {
            onTap();
          },
          child: Container(
            padding: EdgeInsets.fromLTRB(10, 0, 10, 0),
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                Icon(Icons.arrow_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
