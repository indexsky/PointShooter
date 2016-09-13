//
//  GameScene.swift
//  ShiftPoint
//
//  Created by Ashton Wai on 2/25/16.
//  Copyright (c) 2016 Ashton Wai & Zachary Bebel. All rights reserved.
//

struct PhysicsCategory {
    static let None         : UInt32 = 0
    static let All          : UInt32 = UInt32.max
    static let OuterBounds  : UInt32 = 0b1 // 1
    static let PlayBounds   : UInt32 = 0b10 // 2
    static let Enemy        : UInt32 = 0b101 // 4
    static let Player       : UInt32 = 0b1001 // 8
    static let Bullet       : UInt32 = 0b10001 // 16
}

import SpriteKit

class GameScene : SKScene, SKPhysicsContactDelegate {
    var gameManager         : GameManager
    var gamePaused          : Bool
    
    // Bounding boxes
    let playableRect        : CGRect
    let spawnRectBounds     : CGRect
    let spawnZoneBounds     : CGRect
    
    // Player variables
    var player              : Player!
    var lastUpdateTime      : CFTimeInterval = 0
    var deltaTime           : CFTimeInterval = 0
    
    // Game variables
    var pauseOverlay        : SKShapeNode
    var pauseLabel          : SKLabelNode
    var resumeButton        : SKLabelNode
    var scoreLabel          : SKLabelNode = SKLabelNode(fontNamed: Config.Font.MainFont)
    var waveLabel           : SKLabelNode = SKLabelNode(fontNamed: Config.Font.MainFont)
    let maxEnemySize        : CGSize = Config.Enemy.ENEMY_MAX_SIZE
    var numOfEnemies        : Int = 0
    var score               : Int = 0
    var wave                : Int = 1
    var lives               : [SKSpriteNode] = []
    
    
    // MARK: - Initialization -
    init(size: CGSize, scaleMode: SKSceneScaleMode, gameManager: GameManager) {
        self.gameManager = gameManager
        self.gamePaused = false
        self.pauseOverlay = SKShapeNode(rectOfSize: size)
        self.pauseLabel = SKLabelNode(fontNamed: Config.Font.GameOverFont)
        self.resumeButton = SKLabelNode(fontNamed: Config.Font.MainFont)
        
        // make constant for max aspect ratio support 4:3
        let maxAspectRatio: CGFloat = 4.0 / 3.0
        // calculate playable height
        let playableHeight = size.width / maxAspectRatio
        // center playable rectangle on the screen
        let playableMargin = (size.height - playableHeight) / 2.0
        // make centered rectangle on the screen
        playableRect = CGRect(x: 0, y: playableMargin, width: size.width, height: playableHeight)
        
        // Spawn Rects
        spawnRectBounds = CGRect(
            x: playableRect.minX - maxEnemySize.width,
            y: playableRect.minY - maxEnemySize.height,
            width: playableRect.width + maxEnemySize.width * 2,
            height: playableRect.height + maxEnemySize.height * 2
        )
        spawnZoneBounds = CGRect(
            x: playableRect.minX - maxEnemySize.width/2,
            y: playableRect.minY - maxEnemySize.height/2,
            width: playableRect.width + maxEnemySize.width,
            height: playableRect.height + maxEnemySize.height
        )
        
        super.init(size: size)
        
        // Physics for Spawn Rects
        // OuterBounds
        let outerBoundingBox = SKShapeNode()
        outerBoundingBox.path = CGPathCreateWithRect(spawnRectBounds, nil)
        outerBoundingBox.physicsBody = SKPhysicsBody(edgeLoopFromRect: spawnRectBounds)
        outerBoundingBox.physicsBody?.categoryBitMask = PhysicsCategory.OuterBounds
        addChild(outerBoundingBox)
        
        // PlayBounds
        let boundingBox = SKShapeNode()
        boundingBox.path = CGPathCreateWithRect(playableRect, nil)
        boundingBox.physicsBody = SKPhysicsBody(edgeLoopFromRect: playableRect)
        boundingBox.physicsBody?.categoryBitMask = PhysicsCategory.PlayBounds
        addChild(boundingBox)
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMoveToView(view: SKView) {
        playBackgroundMusic("BGM.mp3")
        setupWorld()
        setupHUD()
        spawnWave()
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(GameScene.panDetected(_:)))
        self.view!.addGestureRecognizer(panGesture)
        
        // debug mode
        if Config.Developer.DebugMode {
            debugDrawPlayableArea()
        }
    }
    
    // MARK - Update -
    override func update(currentTime: CFTimeInterval) {
        if !gamePaused {
            if lastUpdateTime > 0 {
                deltaTime = currentTime - lastUpdateTime
            } else {
                deltaTime = 0
            }
            lastUpdateTime = currentTime
            
            enumerateChildNodesWithName("bouncer", usingBlock: { node, stop in
                let bouncer = node as! Bouncer
                self.checkBounds(bouncer)
            })
            
            enumerateChildNodesWithName("seeker", usingBlock: { node, stop in
                let seeker = node as! Seeker
                if let targetLocation = self.player?.position {
                    seeker.seek(self.deltaTime, location: targetLocation)
                }
            })
        }
    }
    
    
    // MARK: - Event Handlers -
    override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {
        for touch in touches {
            let location = touch.locationInNode(self)
            
            if nodeAtPoint(location) == resumeButton {
                resumeButton.fontColor = UIColor.cyanColor()
            }
            
            if !gamePaused {
                player.onTeleport(location)
            }
        }
    }
    
    override func touchesEnded(touches: Set<UITouch>, withEvent event: UIEvent?) { 
        for touch: AnyObject in touches {
            if nodeAtPoint(touch.locationInNode(self)) == resumeButton {
                resumeButton.fontColor = UIColor.whiteColor()
                runUnpauseAction()
            }
        }
    }
    
    func panDetected(recognizer: UIPanGestureRecognizer) {
        if !gamePaused {
            if recognizer.state == .Changed {
                var touchLocation = recognizer.locationInView(recognizer.view)
                touchLocation = self.convertPointFromView(touchLocation)
                
                let dy = player.position.y - touchLocation.y
                let dx = player.position.x - touchLocation.x
                player.direction(dx, dy: dy)
                
                // Shoot bullets
                player.onAutoFire()
            }
            if recognizer.state == .Ended {
                player.stopAutoFire()
            }
        }
    }
    
    
    // MARK - Collision Detections -
    func didBeginContact(contact: SKPhysicsContact) {
        var firstNode: SKNode?
        var secondNode: SKNode?
        
        if contact.bodyA.categoryBitMask < contact.bodyB.categoryBitMask {
            firstNode = contact.bodyA.node
            secondNode = contact.bodyB.node
        } else {
            firstNode = contact.bodyB.node
            secondNode = contact.bodyA.node
        }
        
        guard firstNode != nil else {
            return
        }
        guard secondNode != nil else {
            return
        }
        
        // bounds & bullet collision
        if firstNode?.physicsBody?.categoryBitMask == PhysicsCategory.OuterBounds, let bullet = secondNode as? Bullet {
            bullet.onDestroy()
        }
        // enemy & bullet collision
        if let enemy = firstNode as? Enemy, let bullet = secondNode as? Bullet {
            bulletDidCollideWithEnemy(enemy, thisBullet: bullet)
        }
        // enemy & player collision
        else if let enemy = firstNode as? Enemy, let player = secondNode as? Player {
            playerDidCollideWithEnemy(enemy, thisPlayer: player)
        }
    }
    
    func bulletDidCollideWithEnemy(thisEnemy: Enemy, thisBullet: Bullet) {
        let enemyHp = thisEnemy.hitPoints
        let bulletPower = thisBullet.bulletPower
        
        thisBullet.onHit(enemyHp)
        if thisEnemy.onHit(bulletPower) <= 0 {
            let emitter = thisEnemy.explosion()
            let scoreMarker = thisEnemy.scoreMarker()
            
            runAction(SKAction.sequence([
                SKAction.group([
                    thisEnemy.scoreSound,
                    SKAction.runBlock() {
                        self.addChild(emitter)
                        self.addChild(scoreMarker)
                        
                        self.score += thisEnemy.scorePoints
                        self.scoreLabel.text = "\(self.score)"
                        
                        self.numOfEnemies -= 1
                        if self.numOfEnemies <= 0 {
                            self.wave += 1
                            self.spawnWave()
                        }
                    }
                ]),
                SKAction.waitForDuration(0.3),
                SKAction.runBlock() {
                    emitter.removeFromParent()
                    scoreMarker.runAction(SKAction.sequence([
                        SKAction.fadeOutWithDuration(0.5),
                        SKAction.removeFromParent()
                    ]))
                }
            ]))
        }
    }
    
    func playerDidCollideWithEnemy(thisEnemy: Enemy, thisPlayer: Player) {
        thisEnemy.onDestroy()
        if thisPlayer.onDamaged() {
            let heart = lives.removeLast()
            heart.runAction(SKAction.sequence([
                SKAction.fadeOutWithDuration(0.2),
                SKAction.removeFromParent()
            ]))
        }
        
        if thisPlayer.life <= 0 && !Config.Developer.Endless {
            thisPlayer.onDestroy()
            gameOver()
            return
        }
        
        numOfEnemies -= 1
        if numOfEnemies <= 0 {
            wave += 1
            spawnWave()
        }
    }
    
    func checkBounds(enemy: Enemy) {
        if enemy.position < playableRect {
            // if visible on screen
            enemy.physicsBody?.collisionBitMask = PhysicsCategory.PlayBounds
        }
    }
    
    
    // MARK: - Game Pausing -
    var gameActive: Bool = true {
        didSet {
            lastUpdateTime = 0
            deltaTime = 0
            if !gameActive {
                runPauseAction()
            }
        }
    }
    
    func runPauseAction() {
        // pause game
        pauseGame()
        self.view?.paused = true
    }
    
    func runUnpauseAction() {
        // unpause game
        runAction(SKAction.sequence([
            SKAction.group([
                SKAction.runBlock() {
                    self.pauseLabel.runAction(SKAction.sequence([
                        SKAction.fadeOutWithDuration(0.5),
                        SKAction.removeFromParent()
                    ]))
                },
                SKAction.runBlock() {
                    self.resumeButton.runAction(SKAction.sequence([
                        SKAction.fadeOutWithDuration(0.5),
                        SKAction.removeFromParent()
                    ]))
                },
                SKAction.runBlock() {
                    self.pauseOverlay.runAction(SKAction.sequence([
                        SKAction.fadeOutWithDuration(1.0),
                        SKAction.removeFromParent()
                    ]))
                }
            ]),
            SKAction.waitForDuration(1.0),
            SKAction.runBlock() {
                self.gamePaused = false
                backgroundMusicPlayer.play()
                self.view?.paused = false
            }
        ]))
    }
    
    
    // MARK: - Helper Functions -
    func setupWorld() {
        physicsWorld.gravity = CGVectorMake(0, 0)
        physicsWorld.contactDelegate = self
        
        let background = SKSpriteNode(imageNamed: "Background.jpg")
        background.position = CGPoint(x: size.width/2, y: size.height/2)
        background.zPosition = Config.GameLayer.Background
        background.xScale = 1.45
        background.yScale = 1.45
        addChild(background)
        
        player = Player()
        player.position = CGPointMake(size.width/2, size.height/2)
        player.zPosition = Config.GameLayer.Sprite
        addChild(player)
    }
    
    func setupHUD() {
        let scoreTextLabel = SKLabelNode(fontNamed: Config.Font.MainFont)
        scoreTextLabel.position = CGPointMake(50, size.height-50)
        scoreTextLabel.zPosition = Config.GameLayer.HUD
        scoreTextLabel.horizontalAlignmentMode = .Left
        scoreTextLabel.verticalAlignmentMode = .Top
        scoreTextLabel.fontColor = Config.Font.GameUIColor
        scoreTextLabel.fontSize = Config.Font.GameTextSize
        scoreTextLabel.text = "Score"
        addChild(scoreTextLabel)
        
        scoreLabel.position = CGPoint(x: 50, y: size.height-100)
        scoreLabel.zPosition = Config.GameLayer.HUD
        scoreLabel.horizontalAlignmentMode = .Left
        scoreLabel.verticalAlignmentMode = .Top
        scoreLabel.fontColor = Config.Font.GameUIColor
        scoreLabel.fontSize = Config.Font.GameLabelSize
        scoreLabel.text = "\(score)"
        addChild(scoreLabel)
        
        let waveTextLabel = SKLabelNode(fontNamed: Config.Font.MainFont)
        waveTextLabel.position = CGPointMake(size.width/2, size.height-50)
        waveTextLabel.zPosition = Config.GameLayer.HUD
        waveTextLabel.horizontalAlignmentMode = .Center
        waveTextLabel.verticalAlignmentMode = .Top
        waveTextLabel.fontColor = Config.Font.GameUIColor
        waveTextLabel.fontSize = Config.Font.GameTextSize
        waveTextLabel.text = "Wave"
        addChild(waveTextLabel)
        
        waveLabel.position = CGPointMake(size.width/2, size.height-100)
        waveLabel.zPosition = Config.GameLayer.HUD
        waveLabel.horizontalAlignmentMode = .Center
        waveLabel.verticalAlignmentMode = .Top
        waveLabel.fontColor = Config.Font.GameUIColor
        waveLabel.fontSize = Config.Font.GameLabelSize
        waveLabel.text = "\(wave)"
        addChild(waveLabel)
        
        let lifeTextLabel = SKLabelNode(fontNamed: Config.Font.MainFont)
        lifeTextLabel.position = CGPointMake(size.width-50, size.height-50)
        lifeTextLabel.zPosition = Config.GameLayer.HUD
        lifeTextLabel.horizontalAlignmentMode = .Right
        lifeTextLabel.verticalAlignmentMode = .Top
        lifeTextLabel.fontColor = Config.Font.GameUIColor
        lifeTextLabel.fontSize = Config.Font.GameTextSize
        lifeTextLabel.text = "Life"
        addChild(lifeTextLabel)
        
        for i in 1...player.life {
            let heart = SKSpriteNode(imageNamed: "Heart")
            heart.size = CGSize(width: 55, height: 50)
            let xPos = size.width - (25 + heart.size.width) * CGFloat(i)
            let yPos = size.height - (75 + heart.size.height)
            heart.position = CGPointMake(xPos, yPos)
            heart.zPosition = Config.GameLayer.HUD
            heart.alpha = 0.75
            
            let dot = SKShapeNode(circleOfRadius: 5)
            dot.position = CGPointMake(xPos, yPos)
            dot.zPosition = Config.GameLayer.HUD
            dot.fillColor = Config.Font.GameUIColor
            dot.lineWidth = 0
            dot.alpha = 0.25
            
            addChild(dot)
            addChild(heart)
            lives.append(heart)
        }
    }
    
    func pauseGame() {
        gamePaused = true
        backgroundMusicPlayer.pause()
        
        pauseOverlay.position = CGPointMake(size.width/2, size.height/2)
        pauseOverlay.zPosition = Config.GameLayer.Overlay
        pauseOverlay.fillColor = UIColor.blackColor()
        pauseOverlay.alpha = 0.75
        addChild(pauseOverlay)
        
        pauseLabel = SKLabelNode(fontNamed: Config.Font.GameOverFont)
        pauseLabel.position = CGPointMake(size.width/2, size.height/2+250)
        pauseLabel.zPosition = Config.GameLayer.Overlay
        pauseLabel.fontColor = UIColor.cyanColor()
        pauseLabel.fontSize = 200
        pauseLabel.text = "Paused"
        addChild(pauseLabel)
        
        resumeButton = SKLabelNode(fontNamed: Config.Font.MainFont)
        resumeButton.position = CGPointMake(size.width/2, size.height/2-250)
        resumeButton.zPosition = Config.GameLayer.Overlay
        resumeButton.fontSize = 60
        resumeButton.text = "Resume"
        addChild(resumeButton)
    }
    
    func spawnWave() {
        waveLabel.text = "\(wave)"
        
        // http://www.meta-calculator.com/online/9j13df5xtv8b
        var waveEnemyCount = Int(5.5 * sqrt(0.5 * Double(wave)))
        
        runAction(SKAction.sequence([
            SKAction.waitForDuration(1.0),
            SKAction.runBlock() {
                // Spawn seeker wave once every 3 waves after Wave 5
                if self.wave > 5 && self.wave % 3 == 0 {
                    // Spawn half of enemies as Seekers
                    waveEnemyCount /= 2
                    let circleEnemyCount = self.wave < 16 ? CGFloat(waveEnemyCount) : 16.0
                    let location = CGPoint(x: self.playableRect.width/2, y: self.playableRect.height/2)
                    self.spawnEnemyCircle(EnemyTypes.Seeker, count: circleEnemyCount, center: location, radius: 500)
                }
                self.spawnEnemy(.Bouncer, count: waveEnemyCount)
            }
        ]))
    }
    
    // Spawn outside playableRect
    func getRandomOutsideSpawnLocation() -> CGPoint {
        var location = CGPoint(
            x: CGFloat.random(spawnZoneBounds.minX, max: spawnZoneBounds.maxX),
            y: CGFloat.random(spawnZoneBounds.minY, max: spawnZoneBounds.maxY)
        )
        
        let zone = Int.random(1...4)
        switch zone {
        case 1: location.y = spawnZoneBounds.maxY   // Top
            break
        case 2: location.x = spawnZoneBounds.minX   // Left
            break
        case 3: location.y = spawnZoneBounds.minY   // Bottom
            break
        case 4: location.x = spawnZoneBounds.maxX   // Right
            break
        default: break
        }
        
        return location
    }
    
    // Spawn inside playableRect
    func getRandomInsideSpawnLocation() -> CGPoint {
        let location = CGPoint(
            x: CGFloat.random(playableRect.minX, max: playableRect.maxX),
            y: CGFloat.random(playableRect.minY, max: playableRect.maxY)
        )
        return location
    }
    
    func spawnEnemy(type: EnemyTypes, count: Int) {
        for _ in 0..<count {
            let enemy = createEnemy(type, location: getRandomOutsideSpawnLocation())
            addChild(enemy)
            numOfEnemies += 1
            enemy.move()
        }
    }
    
    func spawnEnemyCircle(type: EnemyTypes, count: CGFloat, center: CGPoint, radius: CGFloat?) {
        let r = (radius != nil) ? radius : (100 + 50 * (count - 1))
        for i in 0..<Int(count) {
            let angle = CGFloat(i) * 360.0 / count
            let pos = CGPointMake(
                center.x + cos(angle * degreesToRadians) * r!,
                center.y + sin(angle * degreesToRadians) * r!)
            let enemy = createEnemy(type, location: pos)
            addChild(enemy)
            numOfEnemies += 1
        }
    }
    
    func gameOver() {
        backgroundMusicPlayer.stop()
        gameManager.loadGameOverScene(score)
    }
    
    
    // MARK: - Debug -
    func debugDrawPlayableArea() {
        let shape = SKShapeNode()
        let path = CGPathCreateMutable()
        CGPathAddRect(path, nil, playableRect)
        shape.path = path
        shape.strokeColor = SKColor.redColor()
        shape.lineWidth = 10.0
        addChild(shape)
    }
}