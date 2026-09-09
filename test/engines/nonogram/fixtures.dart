import 'package:playthepaper/engines/nonogram/nonogram.dart';

/// A 5×5 cross: a bar across the middle and a bar down it.
const crossPicture = ['01110', '00100', '11111', '00100', '01110'];

/// A 5×5 arrow head over a stem.
const arrowPicture = ['00100', '01110', '11111', '00100', '00100'];

NonogramPuzzle crossPuzzle() => NonogramPuzzle.fromPicture(picture: crossPicture, title: 'Cross');

NonogramPuzzle arrowPuzzle() => NonogramPuzzle.fromPicture(picture: arrowPicture, title: 'Arrow');
