import '../CommonHeader.dart';

class AboutUs extends StatelessWidget {
  const AboutUs({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('About Us'),
        centerTitle: true,
        backgroundColor: Colors.amber,
      ),
      body: ListView(
        children: [
          IdentityTile(name: "Tasnim Kabir Sadik", imgae_url: "assets/images/TasnimPhoto.png", fb_url: ""),
          IdentityTile(name: "Abrar Fahyaz", imgae_url: "assets/images/AbrarPhoto.png", fb_url: ""),
          IdentityTile(name: "Sadek Hossain Asif", imgae_url: "assets/images/AsifPhoto.png", fb_url: ""),
          IdentityTile(name: "Anirban Roy Sourov", imgae_url: "assets/images/AnirbanPhoto.png", fb_url: ""),
        ],
      ),
    );
  }
}

class IdentityTile extends StatelessWidget {

  String name;
  String imgae_url;
  String fb_url;

  IdentityTile({
    super.key,
    required this.name,
    required this.imgae_url,
    required this.fb_url,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(10),
      alignment: Alignment.center,
      height: 150.0,
      child: Card(
        child: InkWell(
          splashColor: Colors.amber,
          onTap: () {},
          child: Container(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundImage: AssetImage(imgae_url),
                ),
                SizedBox(
                  width: 20,
                ),
                Expanded(
                  child: Container(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 20.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
