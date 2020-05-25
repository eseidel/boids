import 'dart:ui';

import 'package:flutter/material.dart';
import 'dart:math';

const double kBoidVelocity = 2.0;
const double kBoidScale = 2.0;
const int kBoidCount = 10;
const double kBoidSteerSpeed = .1;
// Governs how much the boids spread out at the start.
const double kInitialWorldSize = 1000;
const double kBoidSenseRadius = 100;
const double kBoidSenseAngle = .75 * pi;

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
    Boid focus = world.mobs[0];
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
    // Paint comes after tick.
  }
}

abstract class Mob {
  Offset position = Offset.zero;
  double radians;
  double velocity;

  Offset get velocityVector => Offset.fromDirection(radians, velocity);

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
  double nextSteeringChange = 0.0;

  List<Offset> nearbyMobs;

  @override
  void tick(World world) {
    radians += nextSteeringChange;
    position += velocityVector;
  }

  @override
  void plan(World world) {
    nextSteeringChange = 0;
    nearbyMobs = <Offset>[];
    // Separation
    if (showSight) {
      for (Mob other in world.mobs) {
        if (other == this) continue;
        Offset offsetToOther = other.position - position;
        if (offsetToOther.distance > kBoidSenseRadius) continue;
        double relativeAngleToOther =
            offsetToOther.direction - velocityVector.direction;
        // print(relativeAngleToOther);
        Offset relativeVector =
            Offset.fromDirection(relativeAngleToOther, offsetToOther.distance);
        nearbyMobs.add(relativeVector);
        // TODO: This is wrong, needs normalization into -pi to +pi first.
        nextSteeringChange += (relativeVector.direction.sign < 0
            ? kBoidSteerSpeed
            : kBoidSteerSpeed);
      }
    }
    // Alignment
    // Cohesion
  }

  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(radians);
    if (showSight) {
      Paint circlePaint = Paint()
        ..color = Colors.grey.withAlpha(30)
        ..strokeWidth = 3.0
        ..style = PaintingStyle.fill;

      var arcRect = Rect.fromCenter(
          center: Offset.zero,
          width: 2 * kBoidSenseRadius,
          height: 2 * kBoidSenseRadius);
      canvas.drawArc(
          arcRect, -kBoidSenseAngle, 2 * kBoidSenseAngle, true, circlePaint);

      if (nearbyMobs.length > 1) {
        print(nearbyMobs);
      }
      for (Offset otherOffset in nearbyMobs) {
        Paint obstaclePaint = Paint()
          ..color = (otherOffset.direction > 0
              ? Colors.red.withAlpha(150)
              : Colors.blue.withAlpha(150))
          ..strokeWidth = 3.0
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset.zero, otherOffset, obstaclePaint);
      }
    }
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
