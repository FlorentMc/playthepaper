import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/where/places.dart';
import '../../../engines/where/where_engine.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../news/story_link.dart';
import '../../play/play_context.dart';
import 'world_map.dart';

/// Where: two clues, one pin on the map, scored by great-circle distance.
class WhereScreen extends StatefulWidget {
  const WhereScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Where',
    paragraphs: [
      'Two clues point to a real place. Tap the map to drop your pin, then submit.',
      'Pinch or scroll to zoom, drag to pan. If you would rather not use the map, Choose from a list lets you pick a city by name.',
      'You are scored on the distance from your pin to the place. Land within the acceptance radius and it counts as solved.',
    ],
  );

  static Future<List<Place>>? _placesFuture;

  static Future<List<Place>> places({AssetBundle? bundle}) => _placesFuture ??= (bundle ?? rootBundle)
      .loadString('assets/map/ne_110m_populated_places_simple.geojson')
      .then((raw) => parsePlaces(jsonDecode(raw) as Map<String, dynamic>));

  @override
  State<WhereScreen> createState() => _WhereScreenState();
}

class _WhereScreenState extends State<WhereScreen> {
  late final WherePuzzle _puzzle;
  late final WhereReveal _reveal;
  late WhereState _state;
  GameResult? _result;
  bool _completing = false;

  PlayContext get play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = WherePuzzle.parse(play.record.payload);
    _reveal = WhereReveal.parse(play.record.reveal);
    _result = play.existingResult();
    final saved = _result == null ? play.loadProgress() : null;
    _state = saved == null ? const WhereState() : WhereState.fromJson(saved);
    if (_result == null && _state.submitted && _state.pinned) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
  }

  Future<void> _placePin(double lat, double lon) async {
    if (_state.submitted || _result != null) return;
    setState(() => _state = _state.withPin(lat, lon));
    await play.saveProgress(_state.toJson());
  }

  Future<void> _chooseFromList() async {
    final place = await showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PlacePicker(),
    );
    if (place != null) await _placePin(place.lat, place.lon);
  }

  Future<void> _submit() async {
    if (!_state.pinned || _state.submitted) return;
    setState(() => _state = _state.submit());
    await play.saveProgress(_state.toJson());
    await _finish();
  }

  Future<void> _finish() async {
    if (_completing || _result != null || !_state.submitted) return;
    _completing = true;
    final distance = _reveal.distanceTo(_state.lat!, _state.lon!);
    final result = GameResult(
      puzzleId: play.record.id,
      completedAt: DateTime.now().toUtc(),
      solved: _reveal.solved(distance),
      distanceKm: distance,
      isArchivePlay: play.isArchivePlay,
    );
    setState(() => _result = result);
    await play.complete(context, result, revealTitle: 'The place', reveal: _revealView(result));
  }

  Widget _revealView(GameResult result) => WhereRevealView(reveal: _reveal, result: result, url: storyUrlFor(play));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final finished = _result != null;
    final showTarget = finished;
    final pin = _state.pinned ? LatLon(_state.lat!, _state.lon!) : null;
    final distance = _result?.distanceKm;

    return GameShell(
      game: play.record.game,
      date: play.record.date,
      difficulty: play.record.difficulty,
      help: WhereScreen.help,
      isArchivePlay: play.isArchivePlay,
      puzzleId: play.record.id.toString(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          FriendLine(challenge: play.challenge),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CLUES', style: theme.textTheme.labelSmall),
                  const SizedBox(height: 6),
                  for (var i = 0; i < _puzzle.clues.length; i++) ...[
                    Text('${i + 1}. ${_puzzle.clues[i]}', style: theme.textTheme.bodyMedium),
                    if (i < _puzzle.clues.length - 1) const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          WorldMap(
            pin: pin,
            target: showTarget ? LatLon(_reveal.lat, _reveal.lon) : null,
            onTap: finished || _state.submitted ? null : _placePin,
            distanceLabel: distance == null || pin == null ? null : formatKm(distance),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.circle, size: 12, color: theme.colorScheme.secondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  pin == null ? 'Pin: tap the map to place it' : 'Pin: ${formatLatLon(pin.lat, pin.lon)}',
                  style: theme.textTheme.labelMedium,
                ),
              ),
              if (showTarget) ...[
                Icon(Icons.diamond, size: 14, color: colors.correct),
                const SizedBox(width: 4),
                Text('Target', style: theme.textTheme.labelMedium),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (finished) ...[
            Text(
              distance == null ? 'Finished' : '${formatKm(distance)} away',
              style: DaypencilTheme.display(size: 28, color: theme.colorScheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              _result!.solved
                  ? 'Within ${formatKm(_reveal.acceptRadiusKm)} · solved'
                  : 'Outside ${formatKm(_reveal.acceptRadiusKm)}',
              style: theme.textTheme.labelMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => play.showResult(context, _result!, revealTitle: 'The place', reveal: _revealView(_result!)),
              child: const Text('See result'),
            ),
          ] else ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.list),
              label: const Text('Choose from a list'),
              onPressed: _state.submitted ? null : _chooseFromList,
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _state.pinned && !_state.submitted ? _submit : null,
              child: const Text('Submit pin'),
            ),
          ],
        ],
      ),
    );
  }
}

/// A searchable list of populated places; pops with the chosen [Place].
class PlacePicker extends StatefulWidget {
  const PlacePicker({super.key, this.bundle});

  final AssetBundle? bundle;

  @override
  State<PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<PlacePicker> {
  late final Future<List<Place>> _places = WhereScreen.places(bundle: widget.bundle);
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search places',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Place>>(
              future: _places,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('The place list could not be loaded.', style: theme.textTheme.bodyMedium));
                }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final matches = snap.data!.where((p) => p.matches(_query)).toList();
                if (matches.isEmpty) {
                  return Center(child: Text('No places match "$_query".', style: theme.textTheme.bodyMedium));
                }
                return ListView.builder(
                  controller: controller,
                  itemCount: matches.length,
                  itemBuilder: (context, i) {
                    final p = matches[i];
                    return ListTile(
                      title: Text(p.name),
                      subtitle: Text(p.country),
                      onTap: () => Navigator.of(context).pop(p),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The place, the distance, whether it was within the radius, the
/// explanation and a story link.
class WhereRevealView extends StatelessWidget {
  const WhereRevealView({super.key, required this.reveal, required this.result, required this.url});

  final WhereReveal reveal;
  final GameResult result;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = result.distanceKm;
    final verdict = d == null
        ? reveal.placeName
        : '${reveal.placeName} · ${formatKm(d)} away · ${reveal.solved(d) ? 'within' : 'outside'} ${formatKm(reveal.acceptRadiusKm)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(verdict, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(formatLatLon(reveal.lat, reveal.lon), style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),
        Text(reveal.explanation, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 6),
        StoryLink(url: url),
      ],
    );
  }
}
