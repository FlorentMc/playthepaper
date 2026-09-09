import 'package:playthepaper/engines/tangram/tangram.dart';

/// The seven pieces put back into the square they came from, the arrangement
/// every other figure is a rearrangement of.
const List<TangramPlacement> squareSolution = [
  TangramPlacement(piece: TangramPiece.largeTriangleA, x: 2, y: 3),
  TangramPlacement(piece: TangramPiece.largeTriangleB, x: 1, y: 2, rotation: 2),
  TangramPlacement(piece: TangramPiece.mediumTriangle, x: 3, y: 1, rotation: 4),
  TangramPlacement(piece: TangramPiece.smallTriangleA, x: 4, y: 3, rotation: 6),
  TangramPlacement(piece: TangramPiece.smallTriangleB, x: 2, y: 1, rotation: 4),
  TangramPlacement(piece: TangramPiece.square, x: 3, y: 2),
  TangramPlacement(piece: TangramPiece.parallelogram, x: 2, y: 1, flipped: true),
];

/// The same square built as a mirror image of [squareSolution], reflected in
/// the line x = 2. Every piece lands somewhere else and the parallelogram is
/// the other way up, but the shape is identical.
const List<TangramPlacement> mirroredSquareSolution = [
  TangramPlacement(piece: TangramPiece.largeTriangleA, x: 2, y: 3),
  TangramPlacement(piece: TangramPiece.largeTriangleB, x: 3, y: 2, rotation: 6),
  TangramPlacement(piece: TangramPiece.mediumTriangle, x: 1, y: 1, rotation: 2),
  TangramPlacement(piece: TangramPiece.smallTriangleA, x: 0, y: 3, rotation: 2),
  TangramPlacement(piece: TangramPiece.smallTriangleB, x: 2, y: 1, rotation: 4),
  TangramPlacement(piece: TangramPiece.square, x: 1, y: 2),
  TangramPlacement(piece: TangramPiece.parallelogram, x: 2, y: 1),
];

/// A second arrangement of the same square, found by search rather than by
/// mirroring: proof that a figure can have more than one answer.
const List<TangramPlacement> otherSquareSolution = [
  TangramPlacement(piece: TangramPiece.largeTriangleA, x: 2, y: 1, rotation: 4),
  TangramPlacement(piece: TangramPiece.largeTriangleB, x: 1, y: 2, rotation: 2),
  TangramPlacement(piece: TangramPiece.mediumTriangle, x: 3, y: 3, rotation: 6),
  TangramPlacement(piece: TangramPiece.smallTriangleA, x: 3, y: 2, rotation: 6),
  TangramPlacement(piece: TangramPiece.smallTriangleB, x: 1, y: 4),
  TangramPlacement(piece: TangramPiece.square, x: 2, y: 3),
  TangramPlacement(piece: TangramPiece.parallelogram, x: 3, y: 2, rotation: 2, flipped: true),
];

TangramPuzzle squarePuzzle() =>
    TangramPuzzle.fromSolution(name: 'Square', placements: squareSolution);
