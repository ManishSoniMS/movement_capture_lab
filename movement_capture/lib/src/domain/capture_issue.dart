/// Declared in display-priority order: when several fail at once,
/// the first one in this list is shown.
enum CaptureIssue {
  multiplePeople,
  noPerson,
  noFace,
  noHands,
  oneHand,
  outOfFrame,
  faceTooFar,
  tooDark,
  tooBright,
  backlit,
}
