import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui';

class Developer {
  final String imagePath;
  final String name;
  final String githubLink;
  final String linkedinLink;

  Developer({
    required this.imagePath,
    required this.name,
    required this.githubLink,
    required this.linkedinLink,
  });
}

final List<Developer> developers = [
  Developer(
    imagePath: 'assets/images/Sadik_picture.png',
    name: 'Tasnim Kabir Sadik',
    githubLink: 'https://github.com/R3dRum92',
    linkedinLink: 'https://www.linkedin.com/in/tasnim-kabir-sadik-1611682a5/',
  ),
  Developer(
    imagePath: 'assets/images/Abrar_picture.png',
    name: 'Abrar Fahyaz',
    githubLink: 'https://github.com/abrr-fhyz',
    linkedinLink: 'https://www.linkedin.com/in/abrar-fahyaz/',
  ),
  Developer(
    imagePath: 'assets/images/Asif_picture.png',
    name: 'Sadek Hossain Asif',
    githubLink: 'https://github.com/CREVIOS',
    linkedinLink: 'https://www.linkedin.com/in/asifsadek/',
  ),
  Developer(
    imagePath: 'assets/images/Anirban_picture.png',
    name: 'Anirban Roy Sourov',
    githubLink: 'https://github.com/point-break-5',
    linkedinLink: 'https://www.linkedin.com/in/anirban-roy-sourov-0a2842248/',
  ),
];

Widget buildInfoCard(
  BuildContext context, {
  required String imagePath,
  required String name,
  required String githubLink,
  required String linkedinLink,
}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        color: Colors.white.withOpacity(0.2),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Handle exception for image not found
            ClipOval(
              child: Image.asset(
                imagePath,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 50,
                    height: 50,
                    color: Colors.grey,
                    child: const Icon(
                      Icons.error,
                      color: Colors.red,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18, // Reduced font size
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                    children: [
                    Container(
                      decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.transparent,
                        ),
                        onPressed: () async =>
                          await launchUrl(Uri.parse(githubLink)),
                        icon: Image.asset(
                          'assets/images/github_logo.png',
                          width: 16,
                          height: 16,
                        ),
                        label: const Text(
                          'Github',
                          style: TextStyle(fontSize: 12, color: Colors.white),
                        ),
                        ),
                      ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.transparent,
                        ),
                        onPressed: () async =>
                          await launchUrl(Uri.parse(linkedinLink)),
                        icon: Image.asset(
                          'assets/images/LinkedIn_Logo.png',
                          width: 16,
                          height: 16,
                        ),
                        label: const Text(
                          'LinkedIn',
                          style: TextStyle(fontSize: 12, color: Colors.white),
                        ),
                        ),
                      ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
