import 'package:flutter/material.dart';

class AppSearchBar extends StatelessWidget {
  const AppSearchBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SearchBar(
      elevation: WidgetStateProperty.all(0.0),
      hintText: 'Search for features',
      hintStyle: WidgetStatePropertyAll(TextStyle(
        color: Colors.white24,
        fontSize: 14,
      )),
      backgroundColor: WidgetStateProperty.all(Color.fromRGBO(39, 39, 39, 1)),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25),
          side: BorderSide(
            color: Colors.white24,
          ),
        ),
      ),
      trailing: [Icon(Icons.search, color: Colors.white24)],
      onTapOutside: (event) {
        FocusScope.of(context).unfocus();
      },
    );
  }
}
