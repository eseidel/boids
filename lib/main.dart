import 'dart:ui';

import 'package:flutter/material.dart';
import 'dart:math';

const double kBoidVelocity = 5.0;
const double kBoidScale = 2.0;
const int kBoidCount = 100;
const double kBoidMaxAvoidSteerSpeed = .1;
// Angles above maxAlignAngle are treeted the same (caps the turn speed).
const double kBoidMaxAlignAngle = pi / 10.0;
const double kBoidMaxAlignSteerSpeed = pi / 100.0;
// Governs how much the boids spread out at the start.
const double kInitialWorldSize = 1000;
const double kBoidSenseRadius = 100;
const double kBoidSenseAngle = .75 * pi;

const bool kEnableSeparation = true;
const bool kEnableAlignment = true;
const bool kEnableCohesion = true;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Boids Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with SingleTickerProviderStateMixin {
  World world;

  void resetWorld() {
    var random = Random();
    world.mobs = List.generate(kBoidCount, (int _) {
      return Boid()
        ..velocity = kBoidVelocity
        ..position = Offset(world.lastKnownSize.width * random.nextDouble(),
            world.lastKnownSize.height * random.nextDouble())
        ..radians = random.nextDouble() * 2.0 * pi
        ..color =
            Color.lerp(Colors.lightBlue, Colors.blue, random.nextDouble());
    });

    Boid focus = world.focusedMob;
    focus.color = Colors.pink;
    focus.showSight = true;
  }

  @override
  void initState() {
    super.initState();
    world = World();
    resetWorld();

    createTicker((Duration elapsed) {
      setState(() {
        world.tick(elapsed);
      });
    }).start();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => resetWorld(),
      child: CustomPaint(
        painter: WorldPainter(world),
        child: SizedBox.expand(),
      ),
    );
  }
}

Offset constrainToSize(Offset offset, Size size) =>
    Offset(offset.dx % size.width, offset.dy % size.height);

class World {
  List<Mob> mobs;
  Size lastKnownSize = Size(kInitialWorldSize, kInitialWorldSize);

  Mob get focusedMob => mobs.first;

  void tick(Duration elapsed) {
    // Move all mobs, if they're outside the bounds, wrap them.
    mobs.forEach(
      (mob) {
        mob.tick(this);
        if (!lastKnownSize.contains(mob.position))
          mob.position = constrainToSize(mob.position, lastKnownSize);
      },
    );
    // Plan the next move for all mobs, including debug details.
    mobs.forEach((mob) {
      mob.plan(this);
    });

    if (kEnableAlignment) {
      mobs.forEach((Mob mob) {
        Boid boid = mob;
        boid.showAngleVector =
            focusedMob.inSensingArea(mob) || mob == focusedMob;
      });
    }
    // Paint comes after tick.
  }
}

abstract class Mob {
  Offset position = Offset.zero;
  double radians;
  double velocity;

  Offset get velocityVector => Offset.fromDirection(radians, velocity);

  bool inSensingArea(Mob mob) => false;
  void paint(Canvas canvas, Size size);
  void tick(World world);
  void plan(World world);
}

class Boid extends Mob {
  Color color;
  Path _path = Path()
    ..moveTo(10, 0)
    ..lineTo(-5, -5)
    ..lineTo(-5, 5)
    ..close();

  bool showSight = false;
  bool showAngleVector = false;
  double nextSteeringChange = 0.0;

  List<Offset> relativeVectorsForNearbyMobs;
  Offset neighborsCentroid;

  @override
  void tick(World world) {
    radians += nextSteeringChange;
    position += velocityVector;
  }

  double normalizeWithinPiToNegativePi(double radians) =>
      ((radians + pi) % (2 * pi) - pi);

  // TODO: This is current linear, quadratic might look better.
  double avoidSteerIntensity(Offset colisionVector) {
    // Steer harder the closer the object is
    // and the more directly in-front it is.
    double angle =
        normalizeWithinPiToNegativePi(colisionVector.direction).abs();
    return (1 - colisionVector.distance / kBoidSenseRadius) *
        (1 - angle / kBoidSenseAngle);
  }

  @override
  bool inSensingArea(Mob other) {
    if (other == this) return false;
    Offset offsetToOther = other.position - position;
    if (offsetToOther.distance > kBoidSenseRadius) return false;
    double relativeAngleToOther =
        offsetToOther.direction - velocityVector.direction;
    relativeAngleToOther = normalizeWithinPiToNegativePi(relativeAngleToOther);
    // Ignore mobs outside our sense angle.
    return (relativeAngleToOther.abs() <= kBoidSenseAngle);
  }

  List<Offset> collectRelativeVectorsForNearbyMobs(World world) {
    List<Offset> nearbyVectors = <Offset>[];
    for (Mob other in world.mobs) {
      if (other == this) continue;
      Offset offsetToOther = other.position - position;
      if (offsetToOther.distance > kBoidSenseRadius) continue;
      double relativeAngleToOther =
          offsetToOther.direction - velocityVector.direction;
      relativeAngleToOther =
          normalizeWithinPiToNegativePi(relativeAngleToOther);
      // Ignore mobs outside our sense angle.
      if (relativeAngleToOther.abs() > kBoidSenseAngle) continue;
      Offset relativeVector =
          Offset.fromDirection(relativeAngleToOther, offsetToOther.distance);
      nearbyVectors.add(relativeVector);
    }
    return nearbyVectors;
  }

  double steerToSeparate() {
    double totalAdjustment = 0.0;
    // Instead of looping and summing, we could just steer away from the closest?
    for (Offset relativeVector in relativeVectorsForNearbyMobs) {
      // Steer away from the angle of the relative vector.
      // At speed relative to how close the mob is
      // and how much in front of us it is.
      double angleAdjust = -relativeVector.direction.sign *
          kBoidMaxAvoidSteerSpeed *
          avoidSteerIntensity(relativeVector);
      totalAdjustment += angleAdjust;
    }
    return totalAdjustment;
  }

  double alignSteerIntensityForAngle(double angleDiff) =>
      (angleDiff / (0.1 * pi));

  double steerToAlign(World world) {
    double averageAngle = 0.0;
    int neighborCount = 0;
    for (Mob mob in world.mobs) {
      if (!inSensingArea(mob)) continue;
      neighborCount += 1;
      averageAngle += normalizeWithinPiToNegativePi(mob.radians);
    }
    if (neighborCount == 0) return 0.0;
    averageAngle /= neighborCount;
    double angleDiff = averageAngle - normalizeWithinPiToNegativePi(radians);
    angleDiff = angleDiff.sign * min(angleDiff.abs(), kBoidMaxAlignAngle);
    // Apply a curved steering adjustment based on diff from average.
    return alignSteerIntensityForAngle(angleDiff) * kBoidMaxAvoidSteerSpeed;
  }

  Offset computeNeighborsCentroid(World world) {
    double xSum = 0;
    double ySum = 0;
    int neighborCount = 0;
    for (Mob mob in world.mobs) {
      if (!inSensingArea(mob)) continue;
      neighborCount += 1;
      xSum += mob.position.dx;
      ySum += mob.position.dy;
    }
    if (neighborCount == 0) return null;
    return Offset(xSum / neighborCount, ySum / neighborCount);
  }

  double steerTowardsMiddle() {
    // TODO: This should use the updated planned velocity vector?
    return (velocityVector.direction - neighborsCentroid.direction) / 100;
  }

  @override
  void plan(World world) {
    nextSteeringChange = 0;
    relativeVectorsForNearbyMobs = collectRelativeVectorsForNearbyMobs(world);
    // Separation
    if (kEnableSeparation) nextSteeringChange += steerToSeparate();
    // Alignment
    if (kEnableAlignment) nextSteeringChange += steerToAlign(world);
    // Cohesion
    if (kEnableCohesion) {
      neighborsCentroid = computeNeighborsCentroid(world);
      if (neighborsCentroid != null) nextSteeringChange += steerTowardsMiddle();
    }
  }

  void paintSightArc(Canvas canvas) {
    Paint circlePaint = Paint()
      ..color = Colors.grey.withOpacity(.1)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.fill;

    var arcRect = Rect.fromCenter(
        center: Offset.zero,
        width: 2 * kBoidSenseRadius,
        height: 2 * kBoidSenseRadius);
    canvas.drawArc(
        arcRect, -kBoidSenseAngle, 2 * kBoidSenseAngle, true, circlePaint);
  }

  void paintDistanceLines(Canvas canvas) {
    for (Offset relativeVector in relativeVectorsForNearbyMobs) {
      Paint obstaclePaint = Paint()
        ..color = Color.lerp(Colors.brown.withOpacity(.3), Colors.red,
            avoidSteerIntensity(relativeVector))
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset.zero, relativeVector, obstaclePaint);
    }
  }

  void paintAngle(Canvas canvas) {
    Paint selfPaint = Paint()
      ..color = (showSight ? Colors.red : Colors.lightBlue)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset.zero, Offset(velocity * 20, 0), selfPaint);
  }

  void paintNeighborsCentroid(Canvas canvas) {
    if (neighborsCentroid == null) return;
    Paint middlePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.fill;
    canvas.drawCircle(neighborsCentroid, 10.0, middlePaint);
  }

  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (showSight && kEnableCohesion) paintNeighborsCentroid(canvas);
    canvas.translate(position.dx, position.dy);
    canvas.rotate(radians);
    if (showSight) {
      paintSightArc(canvas);
      if (kEnableSeparation) paintDistanceLines(canvas);
    }
    if (showAngleVector) paintAngle(canvas);
    canvas.scale(kBoidScale);
    Paint trianglePaint = Paint()
      ..color = color
      ..strokeWidth = 3.0
      ..style = PaintingStyle.fill;
    canvas.drawPath(_path, trianglePaint);
    canvas.restore();
  }
}

class WorldPainter extends CustomPainter {
  final World world;
  WorldPainter(this.world);

  @override
  void paint(Canvas canvas, Size size) {
    // TODO: Remove the lastKnownSize hack.
    world.lastKnownSize = size;
    world.mobs.forEach((mob) {
      mob.paint(canvas, size);
    });
  }

  @override
  bool shouldRepaint(WorldPainter oldDelegate) => true;
}
