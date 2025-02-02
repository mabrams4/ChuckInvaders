/*
--------------------------- Official Version ---------------------------
Additions 
- Get a life if you perfect a wave
- Infinite mode
- make things more clear
- Every "chapter" in campaign has a new soundtrack
*/

// Basic setup stuff
GG.camera().posZ( 10 );
GG.camera().orthographic();
GG.scene().backgroundColor( @(0,0,0) );
GG.lockCursor();
GG.font(me.dir() + "Roboto/Roboto-Regular.ttf");

/* GG.fx() --> BloomFX bloom --> OutputFX output;
bloom.threshold(.2);
bloom.strength(3.0);
bloom.levels(10); */

KB kb;
spork ~ kb.start();
GG.fullscreen();

1.0 => float SPP;  // framebuffer to screen pixel ratio 
// workaround for mac retina displays
if (GG.frameWidth() != GG.windowWidth()) {
    2.0 => SPP;
}

// Global variables
GScene scene;
true => int initializingGame;
false => int gameOver;
false => int gameActive;
false => int gameWon;
float score;
GText scoreText;
GText startGameText;
GText instructionsText;
GText winText;
GText gameOverText;
GText waveText --> scene;
int waveIdx;
float frustrumHeight;
float frustrumWidth;
2::second => dur T; // 4 measures
2::second => dur fourMeas;
fourMeas/16 => dur sNote;
fourMeas/8 => dur eNote;
fourMeas/4 => dur qNote;
fourMeas/2 => dur hNote;
//T - (now % T) => now;
Enemy activeEnemies[0];
Package packages[0];
Bomb bombs[0];
GCircle totalLives[0];
Player player;

// (num_enemies, health, movespeed, value) per wave
[ [10.0, 1, 1.25, 10.0], [10.0, 2.5, 1.5, 15.0] , [12.0, 4, 1.75, 30.0], 
[13.0, 7.5, 2.0, 50.0], [15.0, 10.0, 2.25, 70.0], [10.0, 15.0, 2.5, 100.0],
[13.0, 25.0, 2.0, 500.0] ] 
@=> float waves[][];


fun void UpdateScreenDimensions() 
{
    while (true) 
    {
        GG.frameWidth() / SPP => float screenWidth;
        GG.frameHeight() / SPP => float screenHeight;
        screenWidth / screenHeight => float aspect;
        GG.camera().viewSize() => frustrumHeight;
        frustrumHeight * aspect => frustrumWidth;
        GG.nextFrame() => now;
    }
}
spork ~ UpdateScreenDimensions();

// Make scrolling background
fun void MakeStars()
{
    100 => int numStars;
    GCircle stars[0];
    FlatMaterial flat;

    // make flat material, set up bloom, spork while loop with half second rate, change color from
    // 5,5,5 to .5,.5,.5
    // colors below 1 dont glow in bloom, above will glow

    // initialize stars
    for (int i; i < numStars; i++)
    {
        GCircle s --> scene;
        s.mat(flat);
        s.sca(@(.025, .025, .025));
        stars << s;
        Math.random2f(-frustrumWidth / 2, frustrumWidth / 2) => float x;
        Math.random2f(-frustrumHeight / 2, frustrumHeight / 2) => float y;
        s.pos(@(x, y, 0));
    }

    // pan stars
    spork ~ GlowStars(stars);
    while (true)
    {
        for (GCircle s : stars)
        {
            s.pos() => vec3 currentPos;
            if (currentPos.y < -frustrumHeight / 2)
            {
                Math.random2f(-frustrumWidth / 2, frustrumWidth / 2) => float x;
                s.pos(@(x, frustrumHeight / 2, 0));
            }
            s.translateY(-.5 * GG.dt());
        }
        GG.nextFrame() => now;
    }
    
} spork ~ MakeStars();

fun GlowStars(GCircle stars[])
{
    false => int isGlowing;
    while (true)
    {
        for (GCircle star : stars)
        {
            if (isGlowing) 
            {
                star.mat().color(@(1, 1, 1));
                false => isGlowing;
            }
            else 
            {
                star.mat().color(@(5, 5, 5));
                true => isGlowing;
            }
        }
        .1::second => now;
    }
}

fun void SpawnPackage(vec3 pos)
{
    Package p --> scene;
    packages << p;
    p.Init(pos);
} 

fun float Dot(vec3 v1, vec3 v2)
{
    return (v1.x * v2.x + v1.y * v2.y + v1.z * v2.z);
}

fun int CCDEnemyParticle(Enemy e, ShotParticle p)
{
    p.pos() - e.pos() => vec3 relPos;
    (p.velocityVec - e.movementVector) => vec3 relVel;
    // divide by 2 if square, not if circle
    e.bodySca / 2 + p.scale.x => float sumRadi;

    Dot(relPos, relPos) - sumRadi * sumRadi => float c;
    if (c < 0.0) // if true, they already overlap
        return true;

    Dot(relVel, relVel) => float a;
    Dot(relVel, relPos) => float b;
    if (b > 0.0)
        return false; // does not move towards each other

    b*b - a*c => float d;

    if (d < 0.0)
        return false; // no real roots ... no collision
    //(-b - Math.sqrt(d)) / a => t;
    return false;
}

fun int CCDEnemyPlayer(Enemy e)
{
    player.pos() - e.pos() => vec3 relPos;
    (player.velocityVec - e.movementVector) => vec3 relVel;

    e.bodySca / 2 + player.bodySca / 2 => float sumRadi;

    Dot(relPos, relPos) - sumRadi * sumRadi => float c;
    if (c < 0.0) // if true, they already overlap
        return true;

    Dot(relVel, relVel) => float a;
    Dot(relVel, relPos) => float b;
    if (b > 0.0)
        return false; // does not move towards each other

    b*b - a*c => float d;

    if (d < 0.0)
        return false; // no real roots ... no collision
    //(-b - Math.sqrt(d)) / a => t;
    return false;
}

fun int CCDEnemyShotPlayer(EnemyShot e)
{
    if (gameOver) return false;
    player.pos() - e.pos() => vec3 relPos;
    (player.velocityVec - e.movementVector) => vec3 relVel;

    e.bodySca + player.bodySca / 2 => float sumRadi;

    Dot(relPos, relPos) - sumRadi * sumRadi => float c;
    if (c < 0.0) // if true, they already overlap
        return true;

    Dot(relVel, relVel) => float a;
    Dot(relVel, relPos) => float b;
    if (b > 0.0)
        return false; // does not move towards each other

    b*b - a*c => float d;

    if (d < 0.0)
        return false; // no real roots ... no collision
    //(-b - Math.sqrt(d)) / a => t;
    return false;
}

fun int CCDFallingObjectAndPlayer(GGen object, float dropRate, string type)
{
    player.pos() - object.pos() => vec3 relPos;
    (player.velocityVec - @(0, dropRate, 0)) => vec3 relVel;
    // divide by 2 if square, not if circle
    float objSca;
    if (type == "square")
        object.sca().x / 2 => objSca;
    else if (type == "circle")
        object.sca().x => objSca;

    objSca + player.bodySca / 2 => float sumRadi;

    Dot(relPos, relPos) - sumRadi * sumRadi => float c;
    if (c < 0.0) // if true, they already overlap
        return true;

    Dot(relVel, relVel) => float a;
    Dot(relVel, relPos) => float b;
    if (b > 0.0)
        return false; // does not move towards each other

    b*b - a*c => float d;

    if (d < 0.0)
        return false; // no real roots ... no collision
    //(-b - Math.sqrt(d)) / a => t;
    return false;
}

fun vec3 Normalize(vec3 point)
{
    Math.pow(Math.pow(point.x, 2) + Math.pow(point.y, 2) + Math.pow(point.z, 2), 0.5) => float mag; 
    if (mag == 0)
    {
        return @(0,0,0);
    }
    return @(point.x / mag, point.y / mag, point.z / mag);
}

// Player class
class Player extends GGen
{
    GPlane body --> this;
    int lives;
    Weapon weapons[0];
    3.0 => float movespeed;
    .4 => float bodySca;
    vec3 velocityVec;
    FileTexture chukLogo;
    false => int recentlyDamaged;

    SinOsc s => Envelope e => dac;
    .1 => s.gain;

    fun void Init()
    {
        10 => lives;
        this.pos(@(0,-2,0));
        body.sca(@(bodySca, bodySca+.25, bodySca));
        body.mat().color(Color.WHITE);
        chukLogo.path(me.dir() + "Textures/chuck-logo.png");
        body.mat().diffuseMap(chukLogo);
        body.mat().transparent(true);
        KickGun k;
        AddWeapon(k);
    }

    fun void AddWeapon(Weapon w)
    {
        if (AlreadyHaveWeapon(w))
            w.Upgrade();
        else
        {
            w --> this;
            true => w.active;
            weapons << w;
            spork ~ w.Fire();
        }
    }

    fun int AlreadyHaveWeapon(Weapon w)
    {
        for (Weapon w2 : weapons)
            if (w.weaponName == w2.weaponName) return true;
        return false;
    }

    fun void InvincibilityFrames()
    {
        true => recentlyDamaged;
        2::second => dur invincible;
        now + invincible => time later;
        while (now < later)
        {
            body.mat().alpha() => float alpha;
            while (alpha > 0)
            {
                alpha - .05 => alpha;
                body.mat().alpha(alpha);
                GG.nextFrame() => now;
            }
            while (alpha < 1)
            {
                alpha + .05 => alpha;
                body.mat().alpha(alpha);
                GG.nextFrame() => now;
            }
            GG.nextFrame() => now;
        }
        false => recentlyDamaged;
    }

    fun void TakeDamage()
    {
        if (recentlyDamaged) return;
        lives--;
        totalLives[lives] --< scene;
        spork ~ AnimateDamage();
        spork ~ InvincibilityFrames();
        if (lives <= 0 && !gameOver) 
        {
            true => gameOver;
            this --< scene;
            spork ~ BlowUp();
        }
    }

    fun void AnimateDamage()
    {
        100::ms => dur blinkDur;
        body.mat().color(Color.RED);
        body.sca(@(bodySca * 1.5, (bodySca+.25) * 1.5, bodySca * 1.5));
        blinkDur => now;
        body.sca(@(bodySca, bodySca+.25, bodySca)); 
        body.mat().color(Color.WHITE);
        blinkDur => now;
        body.mat().color(Color.RED);
        body.sca(@(bodySca * 1.5, (bodySca+.25) * 1.5, bodySca * 1.5));
        blinkDur => now;
        body.sca(@(bodySca, bodySca+.25, bodySca)); 
        body.mat().color(Color.WHITE);
    }

    fun void BlowUp()
    {
        GCircle particles[Math.random2(200,400)];
        .5 => float explosionRadius;
        .01 => float particleScale;
        Color.SKYBLUE => vec3 color;
        for (GCircle particle : particles)
        {
            particle --> scene;
            particle.sca(@(particleScale, particleScale, particleScale));
            particle.mat().color(color);
            Math.random2f(0, 2 * Math.PI) => float angle1;
            Math.random2f(0, 2 * Math.PI) => float angle2;
            Math.random2f(0, explosionRadius) => float distance;
            
            this.posX() + distance * Math.sin(angle1) * Math.cos(angle2) => float x;
            this.posY() + distance * Math.sin(angle1) * Math.sin(angle2) => float y;
            particle.pos(@(x, y, this.posZ()));
        }
        particles[0].mat().alpha() => float alpha;
        while (alpha > 0)
        {
            for (GCircle particle : particles)
            {
                particle.pos() - this.pos() => vec3 direction;
                particle.translate(1 * direction * GG.dt());
                particle.mat().alpha(alpha);
            }
            alpha - .005 => alpha;
            GG.nextFrame() => now;
        }
    }

    fun void PowerUpSound()
    {
        sNote => e.duration;
        [64, 71, 76] @=> int notes[];
        Std.mtof(notes[0]) => s.freq;
        e.keyOn();
        50::ms => now;
        e.keyOff();
        Std.mtof(notes[1]) => s.freq;
        e.keyOn();
        50::ms => now;
        e.keyOff();
        Std.mtof(notes[2]) => s.freq;
        e.keyOn();
        50::ms => now;
        e.keyOff();
    }

    fun void CheckDamagingCollisions()
    {
        // check for enemy collisions
        for (int i; i < activeEnemies.size(); i++)
        {
            activeEnemies[i] @=> Enemy e;
            if (CCDEnemyPlayer(e)) 
            {
                TakeDamage();
                if (e.isBoss) e.TakeDamage(1, i);
                else e.TakeDamage(e.health, i);
            }
        }
        // check for bomb collisions
        for (int i; i < bombs.size(); i++)
        {
            bombs[i] @=> Bomb b;
            if (!b.OnScreen()) 
            {
                b --< scene;
                continue;
            }
            if (CCDFallingObjectAndPlayer(bombs[i].body, bombs[i].dropRate, "circle"))
            {
                TakeDamage();
                b --< scene;
                bombs.popOut(i);
            }
        }
    }
    
    fun void DoMovement(float dt)
    {
        if (kb.isKeyDown(kb.KEY_W))
        {
            this.translateY(dt * movespeed);
            @(velocityVec.x, movespeed, velocityVec.z) @=> velocityVec;
        }
        if (kb.isKeyDown(kb.KEY_A))
        {
            this.translateX(-dt * movespeed);
            @(velocityVec.x, -movespeed, velocityVec.z) @=> velocityVec;
        }
        if (kb.isKeyDown(kb.KEY_S))
        {
            this.translateY(-dt * movespeed);
            @(movespeed, velocityVec.y, velocityVec.z) @=> velocityVec;
        }
        if (kb.isKeyDown(kb.KEY_D))
        {
            this.translateX(dt * movespeed);
            @(-movespeed, velocityVec.y, velocityVec.z) @=> velocityVec;
        }
    }

    fun void CheckScreenBounds()
    {
        if (this.posX() <= -(frustrumWidth / 2 + bodySca))
            this.posX(frustrumWidth / 2 + bodySca / 2);
        if (this.posX() >= (frustrumWidth / 2 + bodySca))
            this.posX(-(frustrumWidth / 2 + bodySca / 2));

        if (this.posY() <= -(frustrumHeight / 2 + body.scaY()))
            this.posY(frustrumHeight / 2 + body.scaY() / 2);
        if (this.posY() >= (frustrumHeight / 2 + body.scaY()))
            this.posY(-(frustrumHeight / 2 + body.scaY() / 2));
    }

    fun void update(float dt)
    {
        if (!recentlyDamaged) CheckDamagingCollisions();
        // check for package collisions
        for (int i; i < packages.size(); i++)
        {
            packages[i] @=> Package p;
            if (CCDFallingObjectAndPlayer(p.body, p.dropRate, "square"))
            {
                p --< scene;
                AddWeapon(p.weapon);
                packages.popOut(i);
                spork ~ PowerUpSound();
            }
        }
        DoMovement(dt);
        CheckScreenBounds();
    }
}

// Enemy class
class Enemy extends GGen
{
    // Attributes
    float health;
    float movespeed;
    float shotCooldown;
    float shotSpeed;
    vec3 movementVector;
    vec3 path[];
    0 => int pathIndex;
    .025 => float thresh;
    .33 => float packageSpawnProb;
    false => int waitingToDropBomb;
    false => int isBoss;
    false => int waitingToShoot;
    vec3 color;
    string fileTex;


    // Body
    GPlane body --> this;
    0.5 => float bodySca;

    fun void Init(vec3 pos)
    {
        this --> scene;
        Color.random() => color;
        body.mat().color(color);
        body.sca(@(bodySca, bodySca, bodySca));
        this.pos(pos);
        FileTexture tex;
        tex.path(me.dir() + "Textures/" + fileTex + ".png");
        body.mat().diffuseMap(tex);
        body.mat().transparent(true);
        Math.random2f(3, 5) - waveIdx$float / 10 => shotCooldown;
        Math.random2f(1, 3) + waveIdx$float / 10 => shotSpeed;
    }

    fun void DeathSound()
    {
        SndBuf buf => Gain g => JCRev rev => dac;
        .2 => g.gain;
        .1 => rev.mix;
        me.dir() + "Sounds/explode.wav" => buf.read;
        2.5::second => now;
    }

    fun void BlowUp(int numParticles, float particleScale, float explosionRadius) 
    {
        spork ~ DeathSound();
        GCircle particles[numParticles];
        for (GCircle particle : particles)
        {
            particle --> scene;
            particle.sca(@(particleScale, particleScale, particleScale));
            particle.mat().color(color);
            Math.random2f(0, 2 * Math.PI) => float angle1;
            Math.random2f(0, 2 * Math.PI) => float angle2;
            Math.random2f(0, explosionRadius) => float distance;
            
            this.posX() + distance * Math.sin(angle1) * Math.cos(angle2) => float x;
            this.posY() + distance * Math.sin(angle1) * Math.sin(angle2) => float y;
            particle.pos(@(x, y, this.posZ()));
        }
        this --< scene;
        particles[0].mat().alpha() => float alpha;
        while (alpha > 0)
        {
            for (GCircle particle : particles)
            {
                particle.pos() - this.pos() => vec3 direction;
                particle.translate(1.2 * direction * GG.dt());
                particle.mat().alpha(alpha);
            }
            alpha - .005 => alpha;
            GG.nextFrame() => now;
        }
    }

    // this is sporked
    fun void TakeDamage(float damage, int indx)
    {
        spork ~ AnimateDamage();
        health - damage => health;
        if (health <= 0) 
        {
            if (isBoss) 
            {
                true => gameWon;
                UpdateScore(3000);
                spork ~ BlowUp(400, .02, .5);
            }
            else
            {
                if (Math.random2f(0,1) <= packageSpawnProb) SpawnPackage(this.pos());
                UpdateScore(waves[waveIdx-1][3]);
                spork ~ BlowUp(Math.random2(50,100), .01, bodySca);
            }
            activeEnemies.popOut(indx);
        }
    }

    fun void AnimateDamage()
    {
        body.sca(body.sca() * 1.25);
        50::ms => now;
        body.sca(@(bodySca, bodySca, bodySca));
        if (health <= 0) 
        {
            this --< scene;
        }
    }

    fun vec3 CalculateMovementVec(vec3 targetPoint, float dt)
    {
        Normalize(targetPoint - this.pos()) => vec3 direction;
        return direction * movespeed * dt;
    }

    fun int ReachedTarget(vec3 targetPoint)
    {
        if (Math.euclidean(this.pos(), targetPoint) < thresh) return true;
        return false;
    }

    fun void DropBomb()
    {
        Bomb bomb --> scene;
        bombs << bomb;
        bomb.body.pos(this.pos());
    }

    fun void BombCoolDown()
    {
        Math.random2f(1000, 5000)::ms => now;
        false => waitingToDropBomb;
    }

    fun void Shoot()
    {
        if (IsOffScreen()) return;
        EnemyShot e --> scene;
        e.Init(this.pos(), shotSpeed);
        true => waitingToShoot;
    }

    fun void ShotCooldown()
    {
        shotCooldown::second => now;
        false => waitingToShoot;
    }

    fun int IsOffScreen()
    {
        if (this.posY() <= -(frustrumHeight / 2 + bodySca / 2) ||
            this.posY() >= (frustrumHeight / 2 + bodySca / 2) ||
            this.posX() <= -(frustrumWidth / 2 + bodySca / 2) ||
            this.posX() >= (frustrumWidth / 2 + bodySca / 2))
            {
                return true;
            }
        return false;
    }

    fun void update(float dt)
    {
        // path finding
        if (pathIndex < path.size())
        {
            path[pathIndex] => vec3 targetPoint;
            CalculateMovementVec(targetPoint, dt) => movementVector;

            this.translate(movementVector);
            if (ReachedTarget(targetPoint))
            {
                pathIndex++;
            }
        }
        // if enemy reached end of path and still alive
        if (IsOffScreen() && pathIndex == path.size())
        {
            for (int i; i < activeEnemies.size(); i++)
            {
                if (activeEnemies[i].id() == this.id()) activeEnemies.popOut(i);
            }
            this --< scene;
        }
        // Drop bombs logic
        if (!waitingToDropBomb)
        {
            DropBomb();
            spork ~ BombCoolDown();
            true => waitingToDropBomb;
        }
        if (!waitingToShoot)
        {
            Shoot();
            spork ~ ShotCooldown();
            true => waitingToShoot;
        }
    }
}

// Weapon class
class Weapon extends GGen
{
    float damageModifier;
    string weaponName;
    string shotType;
    dur cooldown;
    float damage;
    float shotTravelSpeed;
    vec3 shotSize;
    vec3 color;
    int active;

    fun ShotParticle GetAttackType()
    {
        if (shotType == "circle") 
        {
            CircleShotParticle c;
            shotSize => c.scale;
            return c;
        }
        if (shotType == "laser")
        {
            LaserShot l;
            shotSize => l.scale;
            return l;
        }
        return null;
    }

    fun void Fire() {}

    fun void InstantiateShot()
    {
        GetAttackType() @=> ShotParticle p;
        color => p.color;
        p.Init(this);
    }

    fun void Sync()
    {
        if (weaponName == "kick gun") T/2 - (now % (T/2)) => now;
        if (weaponName == "snare gun") T - (now % T) => now;
        if (weaponName == "hihat gun") T/2 - (now % (T/2))  + eNote => now;
        if (weaponName == "laser gun 1") T - (now % T) + eNote => now;
        if (weaponName == "laser gun 2") T - (now % T) + eNote => now;
        if (weaponName == "melody gun 1") 2.0*T - (now % (2.0*T)) + qNote => now;
        if (weaponName == "melody gun 2") 2.0*T - (now % (2.0*T)) => now;
        if (weaponName == "melody gun 3") 2.0*T - (now % (2.0*T)) + hNote => now;
    }

    fun void MakeSound() {}

    fun void Upgrade()
    {
        damage + damageModifier => damage;
    }
}

// weapon types
class KickGun extends Weapon
{
    "kick gun" => weaponName;
    "circle" => shotType;
    qNote => cooldown;
    1.0 => damage;
    1 => damageModifier;
    4.0 => shotTravelSpeed;
    @(.05, .05, .05) @=> shotSize;
    Color.WHITE => color;

    fun void Fire()
    {
        SndBuf buf => Gain g => dac;
        .1 => g.gain;
        Sync();
        while (active)
        {
            InstantiateShot();
            me.dir() + "Sounds/kick.wav" => buf.read;
            cooldown => now;
        }
    }
}

class SnareGun extends Weapon
{
    "snare gun" => weaponName;
    "circle" => shotType;
    hNote => cooldown;
    2.0 => damage;
    2 => damageModifier;
    4.0 => shotTravelSpeed;
    @(.15, .15, .15) @=> shotSize;
    Color.BROWN => color;

    fun void Fire()
    {
        SndBuf buf => Gain g => dac;
        .1 => g.gain;
        Sync();
        while (active)
        {
            InstantiateShot();
            me.dir() + "Sounds/snare.wav" => buf.read;
            cooldown => now;
        }
    }
}

class HiHatGun extends Weapon
{
    "hihat gun" => weaponName;
    "circle" => shotType;
    qNote => cooldown;
    1.0 => damage;
    1.0 => damageModifier;
    4.0 => shotTravelSpeed;
    @(.05, .05, .05) @=> shotSize;
    Color.YELLOW => color;

    fun void Fire()
    {
        SndBuf buf => Gain g => dac;
        .1 => g.gain;
        Sync();
        while (active)
        {
            InstantiateShot();
            me.dir() + "Sounds/hihat.wav" => buf.read;
            cooldown => now;
        }
    }
}

class MelodyGun1 extends Weapon
{
    "melody gun 1" => weaponName;
    "circle" => shotType;
    2.0 => damage;
    2.0 => damageModifier;
    5.0 => shotTravelSpeed;
    @(.1, .1, .1) @=> shotSize;
    Color.BLUE => color;
    [69, 71, 72, 71, 77, 65, 69, 57, 57] @=> int notes[];
    0 => int notesIndx;

    fun void Fire()
    {
        Mandolin m => JCRev r => dac;
        .1 => m.gain;
        .2 => r.mix;
        Sync();
        while (active)
        {
            PlayNote(qNote, m); // 1/4

            PlayNote(sNote, m); // 1/16 * 2
            PlayNote(sNote, m); 

            PlayNote(eNote, m); // 1/8 * 5
            PlayNote(eNote, m); 
            PlayNote(eNote, m);
            PlayNote(eNote, m);
            PlayNote(eNote, m);

            PlayNote(T, m); // 1
            0 => notesIndx;
        }
    }

    fun void PlayNote(dur cooldown, Mandolin m)
    {
        InstantiateShot();
        Std.mtof(notes[notesIndx]) => m.freq;
        .5 => m.pluck;
        cooldown => now;
        notesIndx++;
    }
}

class MelodyGun2 extends Weapon
{
    "melody gun 2" => weaponName;
    "circle" => shotType;
    2.0 => damage;
    2.0 => damageModifier;
    5.0 => shotTravelSpeed;
    @(.1, .1, .1) @=> shotSize;
    Color.PINK => color;
    [57, 69, 67, 69, 71, 69] @=> int notes[];
    0 => int notesIndx;

    fun void Fire()
    {
        Saxofony sax => JCRev r => dac; // need new instrument
        Sync();
        .05 => sax.gain;
        .1 => r.mix;
        .5 => sax.stiffness;
        .5 => sax.aperture;
        .25 => sax.noiseGain;
        .25 => sax.blowPosition;
        8 => sax.vibratoFreq;
        .75 => sax.vibratoGain;
        .25 => sax.pressure;
        while (active)
        {
            PlayNote(hNote, sax); // 1/2 

            PlayNote(eNote, sax); // 1/8 * 3
            PlayNote(eNote, sax);
            PlayNote(eNote, sax);

            PlayNote(qNote, sax); // 1/4

            //PlayNote(T -  eNote, sax); // 1 - 1/8
            PlayNote(qNote, sax); // 1 - 1/8
            
            0 => notesIndx;
        }
    }

    fun void PlayNote(dur cooldown, Saxofony s)
    {
        InstantiateShot();
        Std.mtof(notes[notesIndx]) => s.freq;
        .75 => s.noteOn;
        cooldown => now;
        notesIndx++;
    }
}

class MelodyGun3 extends Weapon
{
    "melody gun 3" => weaponName;
    "circle" => shotType;
    2.0 => damage;
    2.0 => damageModifier;
    5.0 => shotTravelSpeed;
    @(.1, .1, .1) @=> shotSize;
    Color.GREEN => color;
    [60, 59, 57, 50, 52] @=> int notes[];
    0 => int notesIndx;

    fun void Fire()
    {
        Mandolin m => JCRev r => dac;
        .1 => m.gain;
        .2 => r.mix;
        Sync();
        while (active)
        {
            PlayNote(eNote, m); // 1/2 
            PlayNote(eNote, m); // 1/8 * 3
            PlayNote(qNote + eNote, m);
            PlayNote(eNote, m);
            PlayNote(T + qNote, m); // 1/4
            0 => notesIndx;
        }
    }

    fun void PlayNote(dur cooldown, Mandolin m)
    {
        InstantiateShot();
        Std.mtof(notes[notesIndx] + 12) => m.freq;
        .75 => m.pluck;
        cooldown => now;
        notesIndx++;
    }
}

class LaserGun extends Weapon
{
    "laser" => shotType;
    sNote => cooldown;
    .25 => damage;
    .25 => damageModifier;
    int notes[];
    float offsets[];

    fun void Init() {}

    fun void InstantiateLaserShot(float offset)
    {
        GetAttackType() @=> ShotParticle p;
        color => p.color;
        p.Init(this);
        p.LaserStuff(offset);
        cooldown => now;
    }
}

class LaserGun1 extends LaserGun
{
    "laser gun 1" => weaponName;
    Color.SKYBLUE => color;
    [69, 65, 57, 65] @=> notes;
    [-2.0, -1.5, -1.0, -.5] @=> offsets;
    
    fun void Fire()
    {
        // sound stuff
        Sync();
        SinOsc s => JCRev r => dac;
        .05 => s.gain;
        .2 => r.mix;
        while (active)
        {
            for (int i; i < notes.size(); i++)
            {
                Std.mtof(notes[i]) => s.freq;
                InstantiateLaserShot(offsets[i]);
            }
        }
    }
}

class LaserGun2 extends LaserGun
{
    "laser gun 2" => weaponName;
    Color.MAGENTA => color;
    [60, 57, 53, 57] @=> notes;
    [2.0, 1.5, 1, .5] @=> offsets;
    
    fun void Fire()
    {
        // sound stuff
        Sync();
        SinOsc s => JCRev r => dac;
        .025 => s.gain;
        .25 => r.mix;
        while (active)
        {
            for (int i; i < notes.size(); i++)
            {
                Std.mtof(notes[i] + 12) => s.freq;
                InstantiateLaserShot(offsets[i]);
            }
        }
    }
}

// Shot Particle class
class ShotParticle extends GGen
{
    Weapon weapon;
    string weaponName;
    vec3 scale;
    vec3 color;
    vec3 velocityVec;
    true => int onScreen;

    fun void Init(Weapon w) {}

    fun void LaserStuff(float offset) {}

    fun void update(float dt) {}
}

class CircleShotParticle extends ShotParticle
{
    fun void Init(Weapon w)
    {
        GCircle body --> this --> scene;
        this.pos(@(player.posX(), player.posY() + player.scaY() / 4, player.posZ()));
        if (w.weaponName == "melody gun 1") this.posX(player.posX() - .15);
        if (w.weaponName == "melody gun 3") this.posX(player.posX() + .15);
        body.sca(scale);
        w @=> weapon;
        w.weaponName => weaponName;
        body.mat().color(color);
    }

    fun void update(float dt)
    {
        this.translateY(weapon.shotTravelSpeed * GG.dt());
        // check collisions
        for (int i; i < activeEnemies.size(); i++)
        {
            activeEnemies[i] @=> Enemy e;
            if (CCDEnemyParticle(e, this))
            {
                e.TakeDamage(weapon.damage, i);
                this --< scene;
            }
        }
        // check if off screen
        if (this.posY() > frustrumHeight / 2 + scale.y) 
        {
            false => onScreen;
            this --< scene;
        }
        @(0, weapon.shotTravelSpeed * dt, 0) => velocityVec;
    }
}

class LaserShot extends ShotParticle
{
    GPlane body --> this;
    .04 => float laserWidth;
    75::ms => dur lifeTime;

    fun void LaserStuff(float offset)
    {
        frustrumHeight - player.posY() => float length;
        player.posX() + (offset * laserWidth * 2) => float x;
        player.posY() + length / 2 + player.body.scaY() / 4 - (Math.fabs(offset) * .1) => float y;

        this.pos(@(x, y, -1));
        body.sca(@(laserWidth, length, 0));
        CCDLaserEnemies();
        spork ~ Fade();
    }

    fun void Init(Weapon w)
    {
        this --> scene;
        w @=> weapon;
        w.weaponName => weaponName;
        body.mat().color(color);
        body.mat().transparent(true);
    }

    fun void CCDLaserEnemies()
    {
        for (int i; i < activeEnemies.size(); i++)
        {
            activeEnemies[i] @=> Enemy e;
            e.posX() + e.bodySca / 2 => float rx;
            e.posX() - e.bodySca / 2 => float lx;

            if (this.posX() <= rx + laserWidth / 2 && this.posX() >= lx - laserWidth / 2
            && player.posY() + player.sca().y / 2 < e.posY() - e.bodySca / 2) 
            {
                e.TakeDamage(weapon.damage, i);
            }
        }
    }

    fun void Fade()
    {
        body.mat().alpha() => float alpha;
        while (alpha > 0)
        {
            body.mat().alpha(alpha);
            alpha - .015 => alpha;
            GG.nextFrame() => now;
        }
        this --< scene;
    }
}

fun void SpawnAllPackages()
{
    ["kick", "snare", "hihat", "laser 1", "laser 2", "melody 1", "melody 2", "melody 3"] @=> string weapons[];
    for (int i; i < weapons.size(); i++)
    {
        Package p --> scene;
        0 => p.dropRate;
        packages << p;
        weapons[i] => p.weaponName;
        p.Init(@(-3 + i, 0, 0));
    }
} //SpawnAllPackages();

// Package class
class Package extends GGen
{
    string weapons[];
    ["kick", "snare", "hihat", "laser 1", "laser 2", "melody 1", "melody 2", "melody 3"] @=> weapons;
    GPlane body --> this;
    string weaponName;
    Weapon weapon;
    Math.random2f(-1, -.5) => float dropRate;
    .2 => float bodySca;

    fun void Init(vec3 pos)
    {
        body.pos(pos);
        body.sca(@(bodySca, bodySca, bodySca));
        
        weapons[Math.random2(0, weapons.size() - 1)] => weaponName;
        if (player.weapons.size() < 4 && weaponName == "melody 2") "melody 1" @=> weaponName;
        
        if (weaponName == "kick")
        {
            KickGun k @=> weapon;
        }
        if (weaponName == "snare")
        {
            SnareGun s @=> weapon;
        }
        if (weaponName == "hihat")
        {
            HiHatGun h @=> weapon;
        }
        if (weaponName == "laser 1")
        {
            LaserGun1 l1 @=> weapon;
        }
        if (weaponName == "laser 2")
        {
            LaserGun2 l2 @=> weapon;
        }
        if (weaponName == "melody 1")
        {
            MelodyGun1 m1 @=> weapon;
        }
        if (weaponName == "melody 2")
        {
            MelodyGun2 m2 @=> weapon;
        }
        if (weaponName == "melody 3")
        {
            MelodyGun3 m3 @=> weapon;
        }
        body.mat().color(weapon.color);
    }

    fun void update(float dt)
    {
        if (body.posY() <= -(frustrumHeight / 2 + bodySca / 2)) this --< scene;
        body.rotateZ(.01);
        body.translateY(dropRate * dt);
    }
}

// Bomb class
class Bomb extends GGen
{
    GCircle body --> this;
    body.sca(@(.05, .05, .05));
    body.mat().color(Color.RED);
    Math.random2f(-4, -1) * .5 => float dropRate;

    fun int OnScreen()
    {
        if (body.posY() <= -(frustrumHeight / 2 + body.sca().x)) return false;
        return true;
    }

    fun void update(float dt)
    {
        if (!OnScreen()) this --< scene;
        body.translateY(dropRate * dt);
    }
}

// Boss class
class Boss extends Enemy
{
    1.5 => bodySca;
    3.5 => shotSpeed;
    .5 => shotCooldown;
    200 => health;
    2.5 => movespeed;
    true => isBoss;
    false => int ascended;
    float maxHealth;
    Color.PURPLE => color;
    GPlane healthBar --> this;
    10::second => dur activeTime;
    2::second => dur dormantTime;
    true => int isActive;
    false => int activeTimerStarted;

    fun void Init()
    {
        this.pos(@(0,3,0));
        this --> scene;
        .1 => thresh;
        FileTexture tex;
        tex.path(me.dir() + "Textures/unity-logo.png");
        body.mat().diffuseMap(tex);
        body.mat().transparent(true);
        body.sca(@(bodySca, bodySca, bodySca));
        health => maxHealth;

        healthBar.pos(@(0, bodySca / 2 + .2, 0));
        healthBar.mat().color(Color.RED);
        healthBar.sca(@(bodySca, .1, bodySca));
    }

    fun void Ascend()
    {
        true => ascended;
        shotSpeed * 1.5 => shotSpeed;
        shotCooldown / 1.75 => shotCooldown;
        movespeed + .75 => movespeed;
        body.mat().color(Color.RED);
    }

    fun void Hibernate()
    {
        false => isActive;
        dormantTime => now;
        true => isActive;
    }

    fun void ActiveTimer()
    {
        true => activeTimerStarted;
        activeTime => now;
        false => isActive;
        false => activeTimerStarted;
    }

    fun void update (float dt)
    {
        // path finding
        path[pathIndex] => vec3 targetPoint;
        if (isActive) 
        {
            if (!activeTimerStarted) spork ~ ActiveTimer();
            CalculateMovementVec(targetPoint, dt) => movementVector;
        }
        else 
        {
            @(0,0,0) => movementVector;
            spork ~ Hibernate();
        }
        this.translate(movementVector);
        if (ReachedTarget(targetPoint))
        {
            pathIndex++;
        }
        if (!waitingToShoot)
        {
            Shoot();
            spork ~ ShotCooldown();
        }
        if (health <= maxHealth / 2 && !ascended) Ascend();

        (maxHealth - (maxHealth - health)) / maxHealth => float percentHealth;
        healthBar.scaX(bodySca * percentHealth);
    }
}

// enemy shot class
class EnemyShot extends GGen
{
    GCircle body --> this;
    0.06 => float bodySca;
    vec3 movementVector;

    fun void Init(vec3 pos, float shotSpeed)
    {
        this.pos(pos);
        body.sca(@(bodySca, bodySca, bodySca));
        body.mat().color(Color.GREEN);
        Normalize(player.pos() - pos) * shotSpeed => movementVector;
    }

    fun void update(float dt)
    {
        this.translate(movementVector * dt);
        if (CCDEnemyShotPlayer(this) && !player.recentlyDamaged)
        {
            player.TakeDamage();
            this --< scene;
        }
    }
}

fun void InitializeScore()
{
    scoreText --> scene;
    scoreText.pos(@(frustrumWidth / 2 - 1.5, -(frustrumHeight / 2) + .5, 0));
    0 => score;
    UpdateScore(0);
}

fun void UpdateScore(float value)
{
    score + value => score;
    scoreText.text("" + score$int);
}

fun void DrawLives()
{
    .2 => float scale;
    @(-frustrumWidth / 2 + scale * 2, -frustrumHeight / 2 + scale * 2, 0) => vec3 basePos;
    FileTexture heart;
    heart.path(me.dir() + "Textures/life.png");
    for (int i; i < player.lives; i++)
    {
        GCircle life --> scene;
        life.mat().transparent(true);
        life.mat().diffuseMap(heart);
        life.sca(@(scale, scale, scale));
        @(basePos.x + scale * 2.1 * i, basePos.y, 0) => vec3 newPos;
        life.pos(newPos);
        totalLives << life;
    }
}

fun vec3[] RandomPath(int points) 
{
    vec3 path[points+1];
    for (0 => int i; i < points; i++) {
        Math.random2f(-frustrumWidth/2, frustrumWidth/2) => float x;
        Math.random2f(-frustrumHeight/2, frustrumHeight/2) => float y;

        @(x, y, 0) => vec3 point;
        point => path[i];
    }
    @(0,-frustrumHeight / 2 - 1, 0) => path[points];
    return path;
}

fun void InitializeWave()
{
    spork ~ WaveText();
    ["alien1", "alien2", "alien3"] @=> string textures[];
    textures[Math.random2(0, textures.size()-1)] @=> string fileTex;
    for (int i; i < waves[waveIdx][0]; i++)
    {
        // create the enemy
        Enemy e;

        RandomPath(10 + 1*waveIdx) @=> e.path;
        waves[waveIdx][1] => e.health;
        waves[waveIdx][2] => e.movespeed;
        fileTex @=> e.fileTex;

        frustrumWidth / 2 + e.bodySca * (i+1) * 1.5 => float startX;
        if (Math.sgn(e.path[0].x) == -1) 
            startX * -1 => startX;

        @(startX, Math.random2f(-frustrumHeight, frustrumHeight), 0) => vec3 pos;
        e.Init(pos);
        activeEnemies << e;
    }
    waveIdx++;
} 

fun void WaveText()
{
    waveText.text("Wave " + (waveIdx));
    waveText.pos(@(-frustrumWidth / 2, 2, -waveIdx));
    1 => float factor;
    while (waveText.posX() <= 0 - .1)
    {
        waveText.translate((@(0,2,-waveIdx) - waveText.pos()) * GG.dt() * factor);
        GG.nextFrame() => now;
    }
    waveText.text("");
}

fun void SpawnBoss()
{
    activeEnemies.clear();
    Boss b;
    RandomPath(100) @=> b.path;
    b.Init();
    activeEnemies << b;
}

fun void ResetGame()
{
    for (Enemy e: activeEnemies) e --< scene;
    for (Bomb b : bombs) b --< scene;
    for (Package p : packages) p --< scene;
    for (GCircle life : totalLives) life --< scene;
    for (Weapon w : player.weapons) 
    {
        w --< player;
        false => w.active;
    }
    activeEnemies.clear();
    bombs.clear();
    packages.clear();
    totalLives.clear();
    player.weapons.clear();
}

fun void StartGame()
{
    winText --< scene;
    gameOverText --< scene;
    startGameText --< scene;
    instructionsText --< scene;
    player --> scene;
    player.Init();
    DrawLives();
    InitializeScore();
    0 => waveIdx;
}

fun void WinGameScreen()
{
    winText --> scene;
    winText.text("You Won!");
    winText.color(Color.GREEN);
    winText.pos(@(0, 2, 1));
    ResetGame();
}

fun void GameOverScreen()
{
    gameOverText --> scene;
    gameOverText.text("Game Over!");
    gameOverText.color(Color.RED);
    gameOverText.pos(@(0, 2, 1));
}

fun void StartGameScreen()
{
    startGameText --> scene;
    startGameText.text("Press Space To Start");
    startGameText.pos(@(0, .5, 0));
    instructionsText --> scene;
    instructionsText.text("Use WASD to Move");
    instructionsText.pos(@(0,-2,0));
    false => initializingGame;
}

// Game loop
while (true) 
{
    if (initializingGame)
    {
        StartGameScreen();
    }
    if (!initializingGame && !gameActive && kb.isKeyDown(kb.KEY_SPACE))
    {
        false => gameOver;
        StartGame();
        true => gameActive;
    }
    if (gameOver && gameActive)
    {
        false => gameActive;
        ResetGame();
        GameOverScreen();
        true => initializingGame;
    }
    if (!gameOver && !gameWon && gameActive && activeEnemies.size() == 0)
    {
        if (waveIdx == waves.size()) SpawnBoss();
        else InitializeWave();
    }
    if (gameWon)
    {
        false => gameActive;
        WinGameScreen();
        false => gameWon;
        true => initializingGame;
    }
    GG.nextFrame() => now;
}