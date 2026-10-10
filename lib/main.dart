// ============================================================
//  خلف الجدار — Khalf Al Jidar (Behind the Wall)
//  نسخة كود واحد كامل — ملف Java واحد بدون أي تبعيات
//
//  التشغيل:
//    javac -encoding UTF-8 KhalfAlJidar.java
//    java KhalfAlJidar
//
//  التحكم:
//    A / D أو الأسهم: حركة   |   Space: قفز   |   J: هجوم
//    K: صدّ (توقيت دقيق)     |   L: الرؤية البديلة (تستهلك البصر)
//    E: تفاعل               |   U: تضحية مؤقتة   |   R: إعادة بعد الموت
// ============================================================

import javax.swing.JFrame;
import javax.swing.JPanel;
import javax.swing.SwingUtilities;
import javax.swing.Timer;
import java.awt.*;
import java.awt.event.*;
import java.awt.geom.Rectangle2D;
import java.util.ArrayList;
import java.util.List;

public final class KhalfAlJidar {
    private KhalfAlJidar() {}

    public static void main(String[] args) {
        SwingUtilities.invokeLater(() -> {
            JFrame frame = new JFrame("خلف الجدار — Behind the Wall");
            frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
            frame.setResizable(false);
            GamePanel panel = new GamePanel();
            frame.setContentPane(panel);
            frame.pack();
            frame.setLocationRelativeTo(null);
            frame.setVisible(true);
            panel.start();
        });
    }
}

// -------------------- لوحة اللعبة والإدخال --------------------

final class GamePanel extends JPanel implements KeyListener {
    public static final int WIDTH = 960, HEIGHT = 540;
    private static final int FPS_DELAY_MS = 16;
    private final Timer timer;
    private final Input input = new Input();
    private final World world = new World();
    private long lastNanos;
    private double accumulator;

    public GamePanel() {
        setPreferredSize(new Dimension(WIDTH, HEIGHT));
        setFocusable(true);
        addKeyListener(this);
        setDoubleBuffered(true);
        timer = new Timer(FPS_DELAY_MS, e -> tick());
    }

    public void start() {
        requestFocusInWindow();
        lastNanos = System.nanoTime();
        timer.start();
    }

    private void tick() {
        long now = System.nanoTime();
        double frame = Math.min(0.05, (now - lastNanos) / 1_000_000_000.0);
        lastNanos = now;
        accumulator += frame;
        final double step = 1.0 / 60.0;
        while (accumulator >= step) {
            world.update(step, input);
            accumulator -= step;
        }
        repaint();
    }

    @Override protected void paintComponent(Graphics graphics) {
        super.paintComponent(graphics);
        Graphics2D g = (Graphics2D) graphics.create();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        world.render(g, getWidth(), getHeight());
        g.dispose();
    }

    @Override public void keyPressed(KeyEvent e) { input.set(e.getKeyCode(), true); }
    @Override public void keyReleased(KeyEvent e) { input.set(e.getKeyCode(), false); }
    @Override public void keyTyped(KeyEvent e) { }

    static final class Input {
        private final boolean[] keys = new boolean[1024];
        private final boolean[] pressed = new boolean[1024];

        void set(int key, boolean down) {
            if (key < 0 || key >= keys.length) return;
            if (down && !keys[key]) pressed[key] = true;
            keys[key] = down;
        }
        boolean down(int key) { return key >= 0 && key < keys.length && keys[key]; }
        boolean consume(int key) {
            if (key < 0 || key >= pressed.length) return false;
            boolean result = pressed[key];
            pressed[key] = false;
            return result;
        }
    }
}

// -------------------- الكيان الأساسي --------------------

abstract class Entity {
    double x, y, vx, vy;
    double w, h;
    boolean alive = true;

    Entity(double x, double y, double w, double h) {
        this.x = x; this.y = y; this.w = w; this.h = h;
    }

    Rectangle2D.Double bounds() { return new Rectangle2D.Double(x, y, w, h); }
}

// -------------------- اللاعب --------------------

final class Player extends Entity {
    static final double MOVE_SPEED = 235.0;
    static final double JUMP_SPEED = -490.0;
    static final double GRAVITY = 1250.0;
    int health = 5;
    int maxHealth = 5;
    double sight = 100.0;
    final double maxSight = 100.0;
    boolean grounded, facingRight = true, vision, parrying, attackActive, dead;
    double parryTimer, attackTimer, invulnerableTimer, sacrificeTimer;
    double respawnX = 70, respawnY = 350;

    Player(double x, double y) { super(x, y, 28, 48); }

    void update(double dt, GamePanel.Input in, World world) {
        if (dead) {
            if (in.consume(KeyEvent.VK_R)) world.restart();
            return;
        }

        double direction = 0;
        if (in.down(KeyEvent.VK_A) || in.down(KeyEvent.VK_LEFT)) direction -= 1;
        if (in.down(KeyEvent.VK_D) || in.down(KeyEvent.VK_RIGHT)) direction += 1;
        vx = direction * MOVE_SPEED;
        if (direction != 0) facingRight = direction > 0;

        if (in.consume(KeyEvent.VK_SPACE) && grounded) {
            vy = JUMP_SPEED;
            grounded = false;
        }
        if (in.consume(KeyEvent.VK_K)) {
            parrying = true;
            parryTimer = 0.17;
        }
        if (in.consume(KeyEvent.VK_J) && attackTimer <= 0) {
            attackTimer = 0.26;
            attackActive = true;
        }
        if (in.consume(KeyEvent.VK_L)) vision = !vision;
        if (in.consume(KeyEvent.VK_E)) world.interact();

        if (vision) {
            sight = Math.max(0, sight - 20 * dt);
            if (sight <= 0) vision = false;
        } else {
            sight = Math.min(maxSight, sight + 8 * dt);
        }

        if (in.consume(KeyEvent.VK_U) && sacrificeTimer <= 0 && sight >= 35) {
            sight -= 35;
            sacrificeTimer = 5.0;
        }

        if (parryTimer > 0) parryTimer -= dt;
        else parrying = false;
        if (attackTimer > 0) attackTimer -= dt;
        else attackActive = false;
        if (invulnerableTimer > 0) invulnerableTimer -= dt;
        if (sacrificeTimer > 0) sacrificeTimer -= dt;

        vy += GRAVITY * dt;
        vy = Math.min(vy, 900);
        x += vx * dt;
        world.resolveHorizontal(this);
        y += vy * dt;
        grounded = false;
        world.resolveVertical(this);
        x = Math.max(0, Math.min(world.worldWidth() - w, x));

        if (y > World.WORLD_FLOOR + 250) hurt(world, 99);
    }

    void hurt(World world, int damage) {
        if (dead || invulnerableTimer > 0) return;
        if (parrying && parryTimer > 0) {
            world.showMessage("صدّ ناجح — Parry!", 0.8);
            sight = Math.min(maxSight, sight + 8);
            return;
        }
        health -= damage;
        invulnerableTimer = 0.9;
        if (health <= 0) {
            health = 0;
            dead = true;
            world.showMessage("سقطت خلف الجدار — اضغط R لإعادة المحاولة", 999);
        }
    }

    void respawn() {
        x = respawnX; y = respawnY; vx = vy = 0;
        health = maxHealth; sight = maxSight;
        dead = false; vision = false; invulnerableTimer = 1;
    }
}

// -------------------- الأعداء والزعيم --------------------

final class Enemy extends Entity {
    final boolean boss;
    int health;
    final int maxHealth;
    double attackCooldown = 1.2;
    double tellTimer;
    boolean telling;
    final double leftBound, rightBound;

    Enemy(double x, double y, boolean boss, double leftBound, double rightBound) {
        super(x, y, boss ? 68 : 34, boss ? 72 : 42);
        this.boss = boss;
        this.health = boss ? 18 : 3;
        this.maxHealth = health;
        this.leftBound = leftBound; this.rightBound = rightBound;
    }

    void update(double dt, Player p, World world) {
        if (!alive || p.dead) return;
        double dx = (p.x + p.w / 2) - (x + w / 2);
        double dist = Math.abs(dx);
        if (dist < (boss ? 260 : 180)) {
            vx = Math.signum(dx) * (boss ? 82 : 58);
        } else {
            vx = 0;
        }
        x += vx * dt;
        x = Math.max(leftBound, Math.min(rightBound - w, x));

        attackCooldown -= dt;
        if (attackCooldown <= 0 && dist < (boss ? 100 : 55)) {
            telling = true;
            tellTimer = boss ? 0.65 : 0.48;
            attackCooldown = boss ? 1.8 : 1.35;
        }
        if (telling) {
            tellTimer -= dt;
            if (tellTimer <= 0) {
                telling = false;
                if (Math.abs((p.x + p.w/2) - (x + w/2)) < (boss ? 115 : 70)
                        && Math.abs(p.y - y) < 100) {
                    p.hurt(world, boss ? 2 : 1);
                }
            }
        }
    }

    void damage(int amount, World world) {
        if (!alive) return;
        health -= amount;
        if (health <= 0) {
            alive = false;
            if (boss) world.bossDefeated();
            else world.showMessage("سقط أحد خدام الأخوية.", 1.2);
        }
    }
}

// -------------------- العالم والمستوى والرسم --------------------

final class World {
    static final double WORLD_FLOOR = 470;
    private final Player player = new Player(70, 350);
    private final List<Rectangle2D.Double> platforms = new ArrayList<>();
    private final List<Rectangle2D.Double> hiddenPlatforms = new ArrayList<>();
    private final List<Enemy> enemies = new ArrayList<>();
    private final List<Secret> secrets = new ArrayList<>();
    private double cameraX;
    private double messageTimer;
    private String message = "";
    private boolean loreFound, bossWon, checkpointReached;
    private final int width = 2400;

    World() { buildLevel(); }

    int worldWidth() { return width; }

    private void buildLevel() {
        platforms.clear(); hiddenPlatforms.clear(); enemies.clear(); secrets.clear();
        platforms.add(new Rectangle2D.Double(0, WORLD_FLOOR, width, 100));
        platforms.add(new Rectangle2D.Double(260, 390, 140, 18));
        platforms.add(new Rectangle2D.Double(500, 330, 130, 18));
        platforms.add(new Rectangle2D.Double(780, 390, 180, 18));
        platforms.add(new Rectangle2D.Double(1120, 340, 150, 18));
        platforms.add(new Rectangle2D.Double(1460, 385, 170, 18));
        hiddenPlatforms.add(new Rectangle2D.Double(650, 290, 110, 16));
        hiddenPlatforms.add(new Rectangle2D.Double(990, 300, 95, 16));
        enemies.add(new Enemy(360, WORLD_FLOOR - 42, false, 300, 600));
        enemies.add(new Enemy(840, WORLD_FLOOR - 42, false, 760, 1080));
        enemies.add(new Enemy(1280, WORLD_FLOOR - 72, true, 1220, 1510));
        secrets.add(new Secret(690, 250, "ذكرى مشوّهة", "صوت سيلين: «لم تكن الأعين تُسرق من أجل الرؤية… بل من أجل شيءٍ خلف الجدار.»"));
        secrets.add(new Secret(1040, 260, "وثيقة المتعقبين", "أمر مختوم: «تُغلق ملفات المفقودين من الحي الفقير. الاستقرار أولاً.»"));
        secrets.add(new Secret(1750, 420, "نقطة حفظ", "وصلت إلى نقطة حفظ آمنة."));
    }

    void update(double dt, GamePanel.Input input) {
        if (messageTimer > 0) messageTimer -= dt;
        player.update(dt, input, this);
        if (player.dead) return;

        for (Enemy e : enemies) {
            e.update(dt, player, this);
            if (!e.alive || !player.attackActive) continue;
            double attackX = player.facingRight ? player.x + player.w : player.x - 48;
            Rectangle2D.Double hit = new Rectangle2D.Double(attackX, player.y + 8, 48, player.h - 12);
            if (hit.intersects(e.bounds())) {
                int damage = player.sacrificeTimer > 0 ? 3 : 1;
                e.damage(damage, this);
            }
        }

        if (player.x > 1710 && !checkpointReached) {
            checkpointReached = true;
            player.respawnX = 1740; player.respawnY = 380;
            showMessage("نقطة حفظ — تقدمك الأساسي محفوظ.", 2.0);
        }
        cameraX = Math.max(0, Math.min(width - GamePanel.WIDTH, player.x - GamePanel.WIDTH * 0.38));
        if (player.x > 2150 && bossWon) {
            showMessage("انتهت النسخة التجريبية. الحقيقة ما زالت خلف الجدار…", 999);
        }
    }

    void resolveHorizontal(Entity entity) {
        for (Rectangle2D.Double p : platforms) {
            if (!entity.bounds().intersects(p)) continue;
            if (entity.vx > 0) entity.x = p.x - entity.w;
            else if (entity.vx < 0) entity.x = p.x + p.width;
        }
    }

    void resolveVertical(Entity entity) {
        List<Rectangle2D.Double> all = new ArrayList<>(platforms);
        if (player.vision) all.addAll(hiddenPlatforms);
        for (Rectangle2D.Double p : all) {
            if (!entity.bounds().intersects(p)) continue;
            if (entity.vy >= 0) {
                entity.y = p.y - entity.h;
                entity.vy = 0;
                if (entity == player) player.grounded = true;
            } else {
                entity.y = p.y + p.height;
                entity.vy = 0;
            }
        }
    }

    void interact() {
        for (Secret s : secrets) {
            if (!s.found && Math.hypot((player.x + player.w/2) - s.x, (player.y + player.h/2) - s.y) < 90) {
                s.found = true;
                if (s.title.equals("نقطة حفظ")) {
                    checkpointReached = true;
                    player.respawnX = player.x; player.respawnY = player.y;
                } else loreFound = true;
                showMessage(s.title + ": " + s.text, 5.5);
                return;
            }
        }
        showMessage("لا يوجد شيء يمكن التفاعل معه هنا.", 1.2);
    }

    void bossDefeated() {
        bossWon = true;
        showMessage("هُزم حارس الجدار الأول. انكشف ختمٌ من أخوية العين الثالثة.", 4.0);
    }

    void showMessage(String text, double seconds) { message = text; messageTimer = seconds; }

    void restart() {
        player.respawn();
        player.x = 70; player.y = 350;
        cameraX = 0; message = ""; messageTimer = 0;
        bossWon = false; loreFound = false; checkpointReached = false;
        buildLevel();
    }

    void render(Graphics2D g, int viewW, int viewH) {
        g.setColor(new Color(12, 12, 18)); g.fillRect(0, 0, viewW, viewH);
        drawBackground(g, viewW, viewH);
        Graphics2D worldG = (Graphics2D) g.create();
        worldG.translate(-cameraX, 0);

        for (Rectangle2D.Double p : platforms) {
            worldG.setColor(new Color(48, 44, 51));
            worldG.fill(p);
            worldG.setColor(new Color(91, 65, 65));
            worldG.drawLine((int)p.x, (int)p.y, (int)(p.x+p.width), (int)p.y);
        }
        if (player.vision) {
            for (Rectangle2D.Double p : hiddenPlatforms) {
                worldG.setColor(new Color(110, 32, 45, 190)); worldG.fill(p);
                worldG.setColor(new Color(255, 90, 105)); worldG.draw(p);
            }
        } else {
            for (Rectangle2D.Double p : hiddenPlatforms) {
                worldG.setColor(new Color(60, 34, 43, 70)); worldG.draw(p);
            }
        }

        for (Secret s : secrets) {
            if (s.found) continue;
            boolean visible = player.vision || s.title.equals("نقطة حفظ");
            if (visible) {
                worldG.setColor(new Color(185, 42, 63, 190));
                worldG.fillOval((int)s.x-7, (int)s.y-7, 14, 14);
            } else {
                worldG.setColor(new Color(75, 45, 55, 110));
                worldG.drawOval((int)s.x-7, (int)s.y-7, 14, 14);
            }
        }

        for (Enemy e : enemies) if (e.alive) {
            worldG.setColor(e.boss ? new Color(94, 20, 31) : new Color(74, 67, 74));
            worldG.fillRoundRect((int)e.x, (int)e.y, (int)e.w, (int)e.h, 8, 8);
            worldG.setColor(new Color(200, 180, 170));
            worldG.drawLine((int)e.x+8, (int)e.y+16, (int)e.x+(int)e.w-8, (int)e.y+16);
            if (e.telling) {
                worldG.setColor(player.vision ? Color.RED : new Color(220, 150, 55));
                worldG.drawOval((int)e.x-7, (int)e.y-8, (int)e.w+14, (int)e.h+16);
            }
            drawHealthBar(worldG, e);
        }

        if (!player.dead) {
            worldG.setColor(player.invulnerableTimer > 0 && ((int)(player.invulnerableTimer*16)%2==0)
                    ? new Color(150, 130, 130, 100) : new Color(183, 178, 180));
            worldG.fillRoundRect((int)player.x, (int)player.y, (int)player.w, (int)player.h, 7, 7);
            worldG.setColor(new Color(25, 22, 30));
            int eyeX = player.facingRight ? (int)player.x+19 : (int)player.x+5;
            worldG.fillOval(eyeX, (int)player.y+12, 5, 4);
            if (player.parrying) {
                worldG.setColor(new Color(220, 205, 175));
                worldG.drawOval((int)player.x-9, (int)player.y-7, (int)player.w+18, (int)player.h+14);
            }
            if (player.attackActive) {
                worldG.setColor(new Color(175, 45, 60, 150));
                int ax = player.facingRight ? (int)(player.x+player.w) : (int)player.x-48;
                worldG.fillOval(ax, (int)player.y+7, 48, 32);
            }
        }
        worldG.dispose();

        drawHud(g, viewW);
        if (messageTimer > 0 && !message.isEmpty()) {
            g.setFont(new Font("Dialog", Font.BOLD, 16));
            FontMetrics fm = g.getFontMetrics();
            int boxW = Math.min(viewW - 40, fm.stringWidth(message) + 34);
            int bx = (viewW - boxW)/2;
            g.setColor(new Color(0,0,0,205)); g.fillRoundRect(bx, viewH-84, boxW, 54, 12, 12);
            g.setColor(new Color(225, 215, 210)); g.drawRoundRect(bx, viewH-84, boxW, 54, 12, 12);
            g.drawString(clip(message, fm, boxW-24), bx+12, viewH-52);
        }
        if (player.dead) {
            g.setColor(new Color(0,0,0,170)); g.fillRect(0,0,viewW,viewH);
            g.setColor(new Color(215,205,205)); g.setFont(new Font("Dialog", Font.BOLD, 30));
            centered(g, "انتهت حياتك", viewW, viewH/2-10);
            g.setFont(new Font("Dialog", Font.PLAIN, 18)); centered(g, "اضغط R لإعادة المحاولة", viewW, viewH/2+28);
        }
    }

    private void drawBackground(Graphics2D g, int w, int h) {
        for (int i=0; i<6; i++) {
            int x = (int)(i*230 - (cameraX*0.22)%230);
            g.setColor(new Color(24+i*2, 22+i, 31+i));
            g.fillRect(x, 100+i*22, 160, h-100-i*22);
            g.setColor(new Color(49, 35, 43));
            g.fillRect(x+25, 145+i*15, 10, 180);
            g.fillRect(x+105, 120+i*18, 8, 210);
        }
        g.setColor(new Color(65, 24, 35, 100));
        g.fillOval(w-190, 70, 110, 110);
        g.setColor(new Color(42, 37, 48));
        g.fillRect(0, 0, w, 12);
    }

    private void drawHud(Graphics2D g, int w) {
        g.setFont(new Font("Dialog", Font.BOLD, 14));
        g.setColor(new Color(235, 225, 220));
        g.drawString("خلف الجدار", 20, 30);
        g.drawString("الصحة", 20, 55);
        for (int i=0; i<player.maxHealth; i++) {
            g.setColor(i < player.health ? new Color(160, 35, 52) : new Color(65, 54, 60));
            g.fillRect(78+i*22, 43, 16, 12);
        }
        g.setColor(new Color(235,225,220)); g.drawString("البصر", 20, 78);
        g.setColor(new Color(45,35,42)); g.fillRoundRect(78, 65, 130, 12, 5, 5);
        g.setColor(player.vision ? new Color(205, 54, 75) : new Color(145, 105, 120));
        g.fillRoundRect(78, 65, (int)(130*player.sight/player.maxSight), 12, 5, 5);
        g.setColor(new Color(210,200,195));
        g.drawString("J هجوم   K صدّ   L رؤية   E تفاعل   U تضحية", Math.max(300, w-440), 28);
        if (player.sacrificeTimer > 0) {
            g.setColor(new Color(245, 75, 80)); g.drawString("التضحية: " + (int)Math.ceil(player.sacrificeTimer), w-150, 55);
        }
    }

    private void drawHealthBar(Graphics2D g, Enemy e) {
        int bw = e.boss ? 90 : 42;
        int x = (int)e.x + ((int)e.w-bw)/2, y = (int)e.y - 14;
        g.setColor(new Color(25,20,25)); g.fillRect(x,y,bw,6);
        g.setColor(e.boss ? new Color(180,35,55) : new Color(165,85,75));
        g.fillRect(x,y,(int)(bw*Math.max(0,e.health)/(double)e.maxHealth),6);
    }

    private static String clip(String s, FontMetrics fm, int maxWidth) {
        if (fm.stringWidth(s) <= maxWidth) return s;
        String ellipsis = "…";
        while (!s.isEmpty() && fm.stringWidth(s + ellipsis) > maxWidth) s = s.substring(0, s.length()-1);
        return s + ellipsis;
    }

    private static void centered(Graphics2D g, String text, int width, int y) {
        FontMetrics fm = g.getFontMetrics();
        g.drawString(text, (width-fm.stringWidth(text))/2, y);
    }

    private static final class Secret {
        final double x, y;
        final String title, text;
        boolean found;
        Secret(double x, double y, String title, String text) {
            this.x=x; this.y=y; this.title=title; this.text=text;
        }
    }
}