import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/src/domain/capture_step.dart';
import 'package:movement_capture/src/domain/face_snapshot.dart';
import 'package:movement_capture/src/domain/hand_topology.dart';
import 'package:movement_capture/src/domain/landmark_track.dart';
import 'package:movement_capture/src/domain/pose_topology.dart';

void main() {
  test('full body: points grouped by region, every region present', () {
    final track = LandmarkTrack(sessionId: 'abc', step: CaptureStep.fullBody)
      ..addPose(
        tMs: 0,
        faceCount: 1,
        image: const Size(720, 1280),
        rotationDegrees: 90,
        pose: const [
          PosePoint(type: PoseJoint.nose, x: 0.123456, y: 0.5, likelihood: 0.99),
          PosePoint(type: PoseJoint.leftThumb, x: 0.6, y: 0.4, likelihood: 0.8),
          PosePoint(type: PoseJoint.rightHeel, x: 0.4, y: 0.95, likelihood: 0.7),
        ],
      )
      ..addPose(
        tMs: 150,
        faceCount: 0,
        image: const Size(720, 1280),
        rotationDegrees: 90,
        pose: const [],
      );

    final json = jsonDecode(jsonEncode(track.toJson(mirrored: false)))
        as Map<String, dynamic>;
    expect(json['format'], 'movement_capture.landmarks');
    expect(json['version'], 1);
    expect(json['sessionId'], 'abc');
    expect(json['step'], 'fullBody');
    expect(json['image'], {
      'width': 720,
      'height': 1280,
      'rotationDegrees': 90,
      'mirrored': false,
    });
    expect(json['sampleCount'], 2);

    final first = (json['frames'] as List).first as Map<String, dynamic>;
    final regions = first['regions'] as Map<String, dynamic>;
    expect(regions.keys.toSet(),
        {'face', 'body', 'leftHand', 'rightHand', 'leftFoot', 'rightFoot'});
    expect(regions['face']['nose'], [0.1235, 0.5, 0.99]);
    expect(regions['leftHand']['leftThumb'], isNotNull);
    expect(regions['rightFoot']['rightHeel'], isNotNull);

    final second = (json['frames'] as List)[1] as Map<String, dynamic>;
    expect(second['t'], 150);
    expect((second['regions'] as Map)['body'], isEmpty);
  });

  test('face: box, angles, landmarks and contours; absent when no face', () {
    final track = LandmarkTrack(sessionId: 'abc', step: CaptureStep.face)
      ..addFace(
        tMs: 0,
        faceCount: 1,
        image: const Size(720, 1280),
        rotationDegrees: 0,
        face: const FaceSnapshot(
          box: Rect.fromLTRB(0.25, 0.3, 0.75, 0.6),
          headEulerX: 2.14,
          headEulerY: null,
          headEulerZ: -1.06,
          landmarks: {'noseBase': Offset(0.5, 0.45)},
          contours: {
            'face': [Offset(0.26, 0.35), Offset(0.27, 0.4)],
          },
        ),
      )
      ..addFace(
        tMs: 150,
        faceCount: 0,
        image: const Size(720, 1280),
        rotationDegrees: 0,
        face: null,
      );

    final json = jsonDecode(jsonEncode(track.toJson(mirrored: true)))
        as Map<String, dynamic>;
    expect((json['image'] as Map)['mirrored'], isTrue);
    final frames = json['frames'] as List;
    final face = (frames.first as Map)['face'] as Map<String, dynamic>;
    expect(face['box'], [0.25, 0.3, 0.75, 0.6]);
    expect(face['headEuler'], [2.1, null, -1.1]);
    expect(face['landmarks']['noseBase'], [0.5, 0.45]);
    expect((face['contours']['face'] as List).length, 2);
    expect((frames[1] as Map).containsKey('face'), isFalse);
  });

  test('empty track reports isEmpty and counts samples', () {
    final track = LandmarkTrack(sessionId: 'x', step: CaptureStep.fullBody);
    expect(track.isEmpty, isTrue);
    track.addPose(
      tMs: 0,
      pose: const [],
      faceCount: 0,
      image: const Size(10, 10),
      rotationDegrees: 0,
    );
    expect(track.isEmpty, isFalse);
    expect(track.length, 1);
  });

  test('hands: two hands, 21 points each, with side', () {
    final hand = HandSnapshot(
      handedness: 'Left',
      score: 0.9,
      points: List.generate(21, (i) => Offset(i / 40, 0.5)),
      depth: List.filled(21, -0.01),
    );
    final track = LandmarkTrack(sessionId: 's', step: CaptureStep.hands)
      ..addHands(
        tMs: 0,
        hands: [hand, hand],
        framesMirrored: false,
        image: const Size(720, 1280),
        rotationDegrees: 90,
      );
    final json = jsonDecode(jsonEncode(track.toJson(mirrored: false)))
        as Map<String, dynamic>;
    final hands = ((json['frames'] as List).first as Map)['hands'] as List;
    expect(hands.length, 2);
    expect((hands.first as Map)['side'], 'right');
    expect(((hands.first as Map)['points'] as Map).length, 21);
    expect((hands.first as Map)['points']['indexTip'], [0.2, 0.5, -0.01]);
  });
}
