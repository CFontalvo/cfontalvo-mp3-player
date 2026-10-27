import 'dart:math';

List<T> buildPlaybackQueue<T>(
  Iterable<T> songs, {
  required bool shuffled,
  Random? random,
}) {
  final queue = List<T>.of(songs);
  if (!shuffled || queue.length < 2) return queue;

  final original = List<T>.of(queue);
  queue.shuffle(random);
  final unchanged = List.generate(
    queue.length,
    (index) => queue[index] == original[index],
  ).every((matches) => matches);

  // Evita que el modo aleatorio parezca no funcionar cuando, por azar,
  // shuffle devuelve exactamente el mismo orden.
  if (unchanged) queue.add(queue.removeAt(0));
  return queue;
}
