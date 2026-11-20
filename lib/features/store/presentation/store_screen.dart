import 'package:flutter/material.dart';

class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key, this.owned = false});

  final bool owned;

  static const collections = [
    ('Avatars', 'My avatars', ['anime_male', 'anime_female']),
    ('Costumes', 'Closet', ['wardrobe', 'wardrobe_extra']),
    ('Pets', 'My pets', ['pets']),
    ('Vehicles', 'My vehicles', ['vehicles']),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: collections.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(owned ? 'Owned items' : 'Store'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              for (final group in collections)
                Tab(text: owned ? group.$2 : group.$1),
            ],
          ),
        ),
        body: TabBarView(children: [
          for (final group in collections)
            if (owned)
              Center(child: Text('No purchased items yet', semanticsLabel: 'No purchased items in ${group.$2}'))
            else
              ListView(padding: const EdgeInsets.all(12), children: [
                if (group.$1 == 'Pets')
                  Card(
                    child: ListTile(
                      title: const Text('Beagle'),
                      subtitle: const Text('View pet'),
                      leading: Image.asset('assets/store/beagle.webp', width: 56),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Beagle')),
                          body: ColoredBox(
                            color: const Color(0xffe6efeb),
                            child: SizedBox.expand(child: InteractiveViewer(
                              child: Image.asset('assets/store/beagle.webp',
                                fit: BoxFit.contain,
                                semanticLabel: 'Standing tricolour beagle'),
                            )),
                          ),
                        ),
                      )),
                    ),
                  ),
                for (final sheet in group.$3)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                      button: true,
                      label: 'Enlarge ${group.$1} collection',
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: Text(group.$1)),
                            body: Center(child: InteractiveViewer(
                              maxScale: 8,
                              child: Image.asset('assets/store/$sheet.webp'),
                            )),
                          ),
                        )),
                        child: Image.asset('assets/store/$sheet.webp'),
                      ),
                    ),
                  ),
              ]),
        ]),
      ),
    );
  }
}
