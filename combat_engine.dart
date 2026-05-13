import 'dart:math';
import 'package:flutter/material.dart';
import 'efectos_cartas.dart';

/// ============================================================
/// CombatEngine — Motor de combate real de KOFIGHT.
/// Procesa estadísticas, efectos de cartas, estados (buffs/debuffs),
/// energía, y resolución por rapidez.
/// Reutilizable para Aventura y Arena.
/// ============================================================

// ======================== MODELOS ======================== //

/// Formación de combate. Define el alcance del luchador.
/// vanguard: solo alcanza a enemigos en vanguardia (range 1)
/// mid: alcanza vanguardia y medio (range 2)
/// rear: alcanza cualquier posición (range 3)
enum Formation { vanguard, mid, rear }

/// Rango de alcance según formación.
int formationRange(Formation f) {
  switch (f) {
    case Formation.vanguard: return 1;
    case Formation.mid: return 2;
    case Formation.rear: return 3;
  }
}

/// Índice de profundidad de cada formación (para targeting).
int formationDepth(Formation f) {
  switch (f) {
    case Formation.vanguard: return 1;
    case Formation.mid: return 2;
    case Formation.rear: return 3;
  }
}

/// Estado temporal aplicado a un luchador (buff o debuff).
class CombatEffect {
  final String type; // 'sangrado', 'stun', 'shield', 'vulnerabilidad'
  int turnsRemaining;
  int value; // puntos de escudo, daño de sangrado, etc.

  CombatEffect({
    required this.type,
    required this.turnsRemaining,
    this.value = 0,
  });

  CombatEffect copy() => CombatEffect(
    type: type,
    turnsRemaining: turnsRemaining,
    value: value,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'turnsRemaining': turnsRemaining,
    'value': value,
  };

  factory CombatEffect.fromJson(Map<String, dynamic> json) => CombatEffect(
    type: json['type'] as String,
    turnsRemaining: (json['turnsRemaining'] as num).toInt(),
    value: (json['value'] ?? 0) as int,
  );
}

/// Representa a un luchador en combate (jugador o enemigo).
class Fighter {
  final String id;
  final String name;
  int hp;
  final int maxHp;
  int force;
  int quickness;
  int agility;
  int resistance;
  int shield; // HP temporal del escudo
  Formation formation;
  final List<CombatEffect> effects;

  Fighter({
    required this.id,
    required this.name,
    required this.hp,
    required this.maxHp,
    this.force = 5,
    this.quickness = 5,
    this.agility = 5,
    this.resistance = 5,
    this.shield = 0,
    this.formation = Formation.vanguard,
    List<CombatEffect>? effects,
  }) : effects = effects ?? [];

  bool get isAlive => hp > 0;
  bool get isStunned => effects.any((e) => e.type == 'stun');
  bool get isVulnerable => effects.any((e) => e.type == 'vulnerabilidad');
  bool get isBleeding => effects.any((e) => e.type == 'sangrado');
  bool get hasPrecisionTotal => effects.any((e) => e.type == 'precision_total');
  bool get hasInamovible => effects.any((e) => e.type == 'inamovible');
  bool get hasCeguera => effects.any((e) => e.type == 'ceguera');
  bool get hasEvasion => effects.any((e) => e.type == 'evasion_espejismo');
  bool get hasPotencia => effects.any((e) => e.type == 'potencia');
  bool get hasCotaEspinas => effects.any((e) => e.type == 'cota_espinas');
  bool get hasSilencio => effects.any((e) => e.type == 'silencio');
  bool get hasNoHeal => effects.any((e) => e.type == 'no_heal');
  bool get hasReflectStatus => effects.any((e) => e.type == 'reflect_status');
  bool get hasAuraOverdrive => effects.any((e) => e.type == 'aura_overdrive');
  bool get hasCongelacion => effects.any((e) => e.type == 'congelacion');
  bool get hasReflejoDestino => effects.any((e) => e.type == 'reflejo_destino');
  /// Retorna el bono de fuerza de efectos temporales (ej. Despertar del Aura)
  int get fuerzaBuff => effects.where((e) => e.type == 'fuerza_buff').fold(0, (s, e) => s + e.value);

  void removeBeneficialEffects() {
    effects.removeWhere((e) => e.type == 'mitigacion' || e.type == 'shield' || e.type == 'potencia' ||
        e.type == 'evasion_espejismo' || e.type == 'cota_espinas' || e.type == 'inamovible' ||
        e.type == 'fuerza_buff' || e.type == 'reflect_status' || e.type == 'reflejo_destino');
    shield = 0;
  }

  void removeDebuff(String type) {
    effects.removeWhere((e) => e.type == type);
  }

  /// Crea un Fighter desde datos de personaje de Supabase.
  factory Fighter.fromCharacterData(Map<String, dynamic> data, {Formation formation = Formation.vanguard}) {
    final int hp = ((data['hp'] ?? 100) as num).toInt();
    final String formStr = data['formation']?.toString() ?? '';
    Formation f = formation;
    if (formStr == 'vanguard') f = Formation.vanguard;
    if (formStr == 'mid') f = Formation.mid;
    if (formStr == 'rear') f = Formation.rear;
    return Fighter(
      id: data['id']?.toString() ?? 'unknown',
      name: data['name']?.toString() ?? data['class_type']?.toString() ?? 'Luchador',
      hp: hp,
      maxHp: hp,
      force: ((data['force'] ?? data['base_force'] ?? 5) as num).toInt(),
      quickness: ((data['quickness'] ?? data['base_quickness'] ?? 5) as num).toInt(),
      agility: ((data['agility'] ?? data['base_agility'] ?? 5) as num).toInt(),
      resistance: ((data['resistance'] ?? data['base_resistance'] ?? 5) as num).toInt(),
      formation: f,
    );
  }

  /// Crea un Fighter enemigo con stats predefinidos.
  factory Fighter.enemy({
    required String id,
    required String name,
    int hp = 30,
    int force = 4,
    int quickness = 4,
    int agility = 4,
    int resistance = 3,
    Formation formation = Formation.vanguard,
  }) {
    return Fighter(
      id: id,
      name: name,
      hp: hp,
      maxHp: hp,
      force: force,
      quickness: quickness,
      agility: agility,
      resistance: resistance,
      formation: formation,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'hp': hp,
    'maxHp': maxHp,
    'force': force,
    'quickness': quickness,
    'agility': agility,
    'resistance': resistance,
    'shield': shield,
    'formation': formation.name,
    'effects': effects.map((e) => e.toJson()).toList(),
  };

  // Puedes añadir fromJson si necesitas instanciar desde el payload
  factory Fighter.fromJson(Map<String, dynamic> json) {
    return Fighter(
      id: json['id'] as String,
      name: json['name'] as String,
      hp: json['hp'] as int,
      maxHp: json['maxHp'] as int,
      force: json['force'] as int? ?? 5,
      quickness: json['quickness'] as int? ?? 5,
      agility: json['agility'] as int? ?? 5,
      resistance: json['resistance'] as int? ?? 5,
      shield: json['shield'] as int? ?? 0,
      formation: FormationsExt.fromString(json['formation'] as String?),
      effects: (json['effects'] as List<dynamic>?)?.map((e) => CombatEffect.fromJson(e as Map<String, dynamic>)).toList() ?? [],
    );
  }
}

extension FormationsExt on Formation {
  static Formation fromString(String? name) {
    if (name == 'mid') return Formation.mid;
    if (name == 'rear') return Formation.rear;
    return Formation.vanguard;
  }
}

/// Un evento individual que ocurrió durante la resolución de un turno.
class CombatEvent {
  final String type; // 'damage', 'heal', 'effect_applied', 'stun_skip', 'shield_absorb', 'bleed_tick', 'card_played'
  final String targetId;
  final String? casterId;
  final int value;
  final String label;
  final Color color;
  final String? particleType; // 'attack', 'defense', 'magic', 'bleed', 'stun', 'vulnerability'
  final String? cardType; // 'attack', 'ataque', 'defense', 'defensa', 'magic', 'buff'

  CombatEvent({
    required this.type,
    required this.targetId,
    this.casterId,
    this.value = 0,
    required this.label,
    this.color = Colors.white,
    this.particleType,
    this.cardType,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'targetId': targetId,
    'casterId': casterId,
    'value': value,
    'label': label,
    'particleType': particleType,
    'cardType': cardType,
    'hexColor': '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}',
  };

  factory CombatEvent.fromJson(Map<String, dynamic> json) {
    Color parsedColor = Colors.white;
    if (json['hexColor'] != null) {
       String hex = (json['hexColor'] as String).replaceAll('#', '');
       if (hex.length == 6) hex = 'FF$hex';
       parsedColor = Color(int.parse(hex, radix: 16));
    } else if (json['color'] != null) {
       parsedColor = Color(json['color'] as int); // Backward compat
    }

    return CombatEvent(
      type: json['type'] as String,
      targetId: json['targetId'] as String,
      casterId: json['casterId'] as String?,
      value: (json['value'] as num?)?.toInt() ?? 0,
      label: json['label'] as String? ?? '',
      color: parsedColor,
      particleType: json['particleType'] as String?,
      cardType: json['cardType'] as String?,
    );
  }
}

/// Resultado completo de la resolución de un turno.
class TurnResult {
  final List<CombatEvent> events;
  final bool playerDefeated;
  final bool allEnemiesDefeated;
  final List<String> specialActions;
  final int playerEnergy;
  final int enemyEnergy;
  /// HP y estado finales de los fighters, tal como los calculó el servidor autoritativo.
  final List<Map<String, dynamic>> finalPlayerState;
  final List<Map<String, dynamic>> finalEnemyState;

  TurnResult({
    required this.events,
    this.playerDefeated = false,
    this.allEnemiesDefeated = false,
    this.specialActions = const [],
    this.playerEnergy = 0,
    this.enemyEnergy = 0,
    this.finalPlayerState = const [],
    this.finalEnemyState = const [],
  });

  Map<String, dynamic> toJson() => {
    'events': events.map((e) => e.toJson()).toList(),
    'playerDefeated': playerDefeated,
    'allEnemiesDefeated': allEnemiesDefeated,
    'specialActions': specialActions,
    'playerEnergy': playerEnergy,
    'enemyEnergy': enemyEnergy,
    'finalPlayerState': finalPlayerState,
    'finalEnemyState': finalEnemyState,
  };

  factory TurnResult.fromJson(Map<String, dynamic> json) => TurnResult(
    events: (json['events'] as List<dynamic>?)?.map((e) => CombatEvent.fromJson(e)).toList() ?? [],
    playerDefeated: json['playerDefeated'] as bool? ?? false,
    allEnemiesDefeated: json['allEnemiesDefeated'] as bool? ?? false,
    specialActions: (json['specialActions'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    playerEnergy: (json['playerEnergy'] as num?)?.toInt() ?? 0,
    enemyEnergy: (json['enemyEnergy'] as num?)?.toInt() ?? 0,
    finalPlayerState: (json['finalPlayerState'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
    finalEnemyState: (json['finalEnemyState'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
  );
}

/// Decisión de turno de la IA, devolviendo las asignaciones, energía gastada y cartas a descartar.
class EnemyTurnDecision {
  final Map<String, List<Map<String, dynamic>>> assignments;
  final int energySpent;
  final List<Map<String, dynamic>> discardedCards;

  const EnemyTurnDecision({
    this.assignments = const {},
    this.energySpent = 0,
    this.discardedCards = const [],
  });
}

class ActionSlot {
  final Fighter fighter;
  final Map<String, dynamic> card;
  final bool isPlayer;

  ActionSlot({
    required this.fighter,
    required this.card,
    required this.isPlayer,
  });
}

// ======================== ENGINE ======================== //

class CombatEngine {
  static const int startingEnergy = 3;
  static const int energyPerTurn = 3;
  static const int maxEnergy = 10;

  // Daño por sangrado (ignora resistencia)
  static const int bleedDamage = 5;
  static const int bleedDuration = 3;

  // Multiplicador de vulnerabilidad
  static const double vulnerabilityMultiplier = 1.5;
  static const int vulnerabilityDuration = 2;

  static const int stunDuration = 1;

  final Random _rng = Random();

  // ============== CÁLCULO DE DAÑO ============== //

  /// Calcula el daño final de una carta de ataque.
  /// DañoFinal = max(1, (DañoBase + Fuerza×2) − Resistencia)
  int calculateDamage({
    required int baseDamage,
    required Fighter attacker,
    required Fighter defender,
  }) {
    // Bonificador de fuerza: +2 por cada punto de fuerza
    int attackPower = baseDamage + (attacker.force * 2);

    // Mitigación por resistencia: -1 por cada punto
    int mitigated = attackPower - defender.resistance;

    // Multiplicador de vulnerabilidad
    if (defender.isVulnerable) {
      mitigated = (mitigated * vulnerabilityMultiplier).round();
    }

    // Daño mínimo siempre 1
    return max(1, mitigated);
  }

  // ============== APLICACIÓN DE EFECTOS ============== //

  /// Aplica un escudo al luchador.
  void applyShield(Fighter fighter, int value) {
    fighter.shield += value;
    // También añadir el efecto para tracking visual (dura 1 turno)
    fighter.effects.add(CombatEffect(
      type: 'shield',
      turnsRemaining: 1,
      value: value,
    ));
  }

  /// Aplica sangrado al luchador.
  void applySangrado(Fighter fighter) {
    // Si ya tiene sangrado, refrescar duración
    final existing = fighter.effects.where((e) => e.type == 'sangrado').toList();
    if (existing.isNotEmpty) {
      existing.first.turnsRemaining = bleedDuration;
    } else {
      fighter.effects.add(CombatEffect(
        type: 'sangrado',
        turnsRemaining: bleedDuration,
        value: bleedDamage,
      ));
    }
  }

  /// Aplica stun al luchador.
  void applyStun(Fighter fighter) {
    if (!fighter.isStunned) {
      fighter.effects.add(CombatEffect(
        type: 'stun',
        turnsRemaining: stunDuration,
      ));
    }
  }

  /// Aplica vulnerabilidad al luchador.
  void applyVulnerabilidad(Fighter fighter) {
    final existing = fighter.effects.where((e) => e.type == 'vulnerabilidad').toList();
    if (existing.isNotEmpty) {
      existing.first.turnsRemaining = vulnerabilityDuration;
    } else {
      fighter.effects.add(CombatEffect(
        type: 'vulnerabilidad',
        turnsRemaining: vulnerabilityDuration,
      ));
    }
  }

  /// Aplica daño al luchador, el escudo absorbe primero.
  /// Retorna el daño real aplicado al HP.
  int applyDamage(Fighter target, int rawDamage) {
    if (rawDamage <= 0) return 0;

    int remaining = rawDamage;

    // Escudo absorbe primero
    if (target.shield > 0) {
      if (target.shield >= remaining) {
        target.shield -= remaining;
        return 0; // Todo absorbido por escudo
      } else {
        remaining -= target.shield;
        target.shield = 0;
      }
    }

    // Daño real al HP
    target.hp = max(0, target.hp - remaining);
    return remaining;
  }

  /// Cura HP sin exceder maxHp.
  int applyHeal(Fighter target, int amount) {
    final before = target.hp;
    target.hp = min(target.maxHp, target.hp + amount);
    return target.hp - before;
  }

  // ============== TICK DE EFECTOS (FIN DE TURNO) ============== //

  /// Procesa los efectos al final del turno de un luchador.
  /// Retorna eventos generados (sangrado, expiración de escudo, etc).
  List<CombatEvent> tickEffects(Fighter fighter) {
    final events = <CombatEvent>[];

    // Procesar sangrado
    final bleedEffects = fighter.effects.where((e) => e.type == 'sangrado').toList();
    for (final bleed in bleedEffects) {
      fighter.hp = max(0, fighter.hp - bleed.value);
      events.add(CombatEvent(
        type: 'bleed_tick',
        targetId: fighter.id,
        value: bleed.value,
        label: '¡SANGRADO! -${bleed.value}',
        color: const Color(0xFFB71C1C),
        particleType: 'bleed',
      ));
    }

    // Veneno (-10 HP)
    final poisons = fighter.effects.where((e) => e.type == 'veneno').toList();
    for (var _ in poisons) {
      fighter.hp = max(0, fighter.hp - 10);
      events.add(CombatEvent(
        type: 'damage',
        targetId: fighter.id,
        value: 10,
        label: '-10 VENENO',
        color: Colors.purple,
        particleType: 'poison',
      ));
    }

    // Reducir duración de efectos temporales (excepto pasivos con -1)
    for (final effect in fighter.effects) {
      if (effect.turnsRemaining > 0) {
        effect.turnsRemaining--;
      }
    }

    // Eliminar efectos expirados
    fighter.effects.removeWhere((e) => e.turnsRemaining == 0);

    return events;
  }

  // ============== EJECUCIÓN DE CARTAS ============== //

  /// Ejecuta una carta delegando la lógica al "Cerebro" (EfectosCartas).
  CardResult executeCard({
    required Fighter caster,
    required Map<String, dynamic> card,
    required Fighter primaryTarget,
    required List<Fighter> enemiesOfCaster,
    required List<Fighter> alliesOfCaster,
    int playerHandCount = 0,
  }) {
    final String type = (card['type']?.toString().toLowerCase()) ?? 'attack';
    
    // Determinar la lista potencial de objetivos (ataque va a enemigos, soporte/defensa a aliados)
    List<Fighter> possibleTargets = (type == 'attack' || type == 'ataque') ? enemiesOfCaster : alliesOfCaster;
    
    // Asegurar que primaryTarget esté primero si aplica
    final targets = possibleTargets.where((t) => t.isAlive && t.id != primaryTarget.id).toList();
    
    // Solo agregamos el primaryTarget si está en la lista de posibles targets y está vivo
    if (primaryTarget.isAlive && possibleTargets.any((t) => t.id == primaryTarget.id)) {
      targets.insert(0, primaryTarget);
    } else if (primaryTarget.isAlive) {
      // Si el objetivo principal no está en la lista de potenciales (ej: usó carta de cura pero targeteó enemigo),
      // el objetivo primario pasa a ser él mismo (autocasteo).
      targets.insert(0, caster);
    }

    if (targets.isEmpty) return const CardResult(events: []);

    return EfectosCartas.calculateResult(
      card: card,
      attacker: caster,
      targets: targets,
      playerHandCount: playerHandCount,
    );
  }

  // ============== RESOLUCIÓN DE TURNO COMPLETO ============== //

  /// Resuelve un turno completo: equipo de jugadores vs enemigos.
  TurnResult resolveTurnGlobal({
    required List<Fighter> playerTeam,
    required Map<String, List<Map<String, dynamic>>> playerCardAssignments,
    required List<Fighter> enemies,
    required Map<String, List<Map<String, dynamic>>> enemyCardAssignments,
    required int currentEnergy,
    required Function(int) onEnergyChanged,
    Map<String, String>? targetOverrides, // playerId -> enemyId (manual targeting)
    int playerHandCount = 0,
  }) {
    final allEvents = <CombatEvent>[];
    final allSpecialActions = <String>[];
    int energy = currentEnergy;

    // 1. Recopilar todas las acciones en un solo pool (ActionSlots)
    final List<ActionSlot> actionPool = [];

    // Acciones de jugadores
    for (final playerFighter in playerTeam) {
      if (!playerFighter.isAlive) continue;
      final cardsForPlayer = playerCardAssignments[playerFighter.id] ?? [];
      for (final card in cardsForPlayer) {
        actionPool.add(ActionSlot(
          fighter: playerFighter, 
          card: card, 
          isPlayer: true
        ));
      }
    }

    // Acciones de enemigos
    for (final enemyFighter in enemies) {
      if (!enemyFighter.isAlive) continue;
      final cardsForEnemy = enemyCardAssignments[enemyFighter.id] ?? [];
      for (final card in cardsForEnemy) {
        actionPool.add(ActionSlot(
          fighter: enemyFighter, 
          card: card, 
          isPlayer: false
        ));
      }
    }

    // 2. Ordenar Línea de Iniciativa Global (descendente por quickness, luego agility, luego aleatorio guiado)
    actionPool.sort((a, b) {
       int q = b.fighter.quickness.compareTo(a.fighter.quickness);
       if (q != 0) return q;
       
       int ag = b.fighter.agility.compareTo(a.fighter.agility);
       if (ag != 0) return ag;

       // Desempate aleatorio si todo es igual
       return _rng.nextBool() ? 1 : -1; 
    });

    // Imprimir para DebugGING en consola
    if (actionPool.isNotEmpty) {
      debugPrint('=== LÍNEA DE INICIATIVA ===');
      for (int i = 0; i < actionPool.length; i++) {
        final slot = actionPool[i];
        debugPrint('${i+1}. ${slot.fighter.name} (Q:${slot.fighter.quickness}) — ${slot.card['name']} → [${slot.isPlayer ? 'Jugador' : 'Enemigo'}]');
      }
    }

    // 3. Ejecutar la línea de iniciativa en orden
    for (final slot in actionPool) {
       final caster = slot.fighter;
       
       // a) Saltar si murió antes de su turno
       if (!caster.isAlive) continue;

       // b) Comprobar Stun
       if (caster.isStunned) {
          caster.effects.removeWhere((e) => e.type == 'stun');
          allEvents.add(CombatEvent(
            type: 'stun_skip',
            targetId: caster.id,
            label: '¡ATURDIDO! Turno perdido',
            color: Colors.amber,
            particleType: 'stun',
          ));
          continue;
       }

       // c) Lógica para Jugadores (Costo de Energía)
       if (slot.isPlayer) {
          final int cost = ((slot.card['cost'] ?? 0) as num).toInt();
          if (cost > energy) {
            allEvents.add(CombatEvent(
              type: 'stun_skip',
              targetId: caster.id,
              label: '¡SIN ENERGÍA!',
              color: Colors.orangeAccent,
            ));
            continue;
          }
          energy -= cost;
          onEnergyChanged(energy);
       }

       // d) Targeting
       Fighter? target;
       if (slot.isPlayer) {
         if (targetOverrides != null && targetOverrides.containsKey(caster.id)) {
           final overrideId = targetOverrides[caster.id]!;
           final manualTarget = enemies.where((e) => e.id == overrideId && e.isAlive).firstOrNull;
           if (manualTarget != null) {
             final range = formationRange(caster.formation);
             final depth = formationDepth(manualTarget.formation);
             if (depth <= range) target = manualTarget;
           }
         }
         target ??= _findValidTargetByFormation(caster, enemies);
       } else {
         // Enemigo AI targeting automático
         target = _findValidTargetByFormation(caster, playerTeam);
       }

       // e) Ejecutar Carta
       if (target != null) {
          final enemiesOfCaster = slot.isPlayer ? enemies : playerTeam;
          final alliesOfCaster = slot.isPlayer ? playerTeam : enemies;
          final handCount = slot.isPlayer ? playerHandCount : 0;
          
          final result = executeCard(
            caster: caster, 
            card: slot.card, 
            primaryTarget: target, 
            enemiesOfCaster: enemiesOfCaster, 
            alliesOfCaster: alliesOfCaster, 
            playerHandCount: handCount
          );
          
          allEvents.addAll(result.events);
          allSpecialActions.addAll(result.specialActions);
          
          if (slot.isPlayer) {
             energy += result.energyChange;
             onEnergyChanged(energy);
          }
       }
       
       // Verificación temprana de victoria/derrota para detener la resolución
       if (enemies.every((e) => !e.isAlive) || playerTeam.every((p) => !p.isAlive)) {
          break;
       }
    }

    // Comprobar muertes antes del DoT
    final anyPlayerAlive = playerTeam.any((p) => p.isAlive);
    final allEnemiesDead = enemies.every((e) => !e.isAlive);
    if (!anyPlayerAlive || allEnemiesDead) {
      return TurnResult(
        events: allEvents,
        playerDefeated: !anyPlayerAlive,
        allEnemiesDefeated: allEnemiesDead,
        specialActions: allSpecialActions,
      );
    }

    // 4. Tick de efectos DoT (fin de turno)
    for (final p in playerTeam) {
      if (p.isAlive) allEvents.addAll(tickEffects(p));
    }
    for (final enemy in enemies) {
      if (enemy.isAlive) allEvents.addAll(tickEffects(enemy));
    }

    // Comprobar muertes posteriores al DoT
    final playersAlivePostTick = playerTeam.any((p) => p.isAlive);
    final enemiesDeadPostTick = enemies.every((e) => !e.isAlive);

    // 5. Recuperar energía global al terminar
    energy = min(maxEnergy, energy + energyPerTurn);
    onEnergyChanged(energy);

    return TurnResult(
      events: allEvents,
      playerDefeated: !playersAlivePostTick,
      allEnemiesDefeated: enemiesDeadPostTick,
      specialActions: allSpecialActions,
    );
  }

  // ============== IA DE ENEMIGOS ============== //

  /// Genera cartas para los enemigos basándose en la mano de la IA y su energía disponible
  EnemyTurnDecision generateEnemyAssignments({
    required List<Fighter> enemies,
    required Fighter player,
    required List<Map<String, dynamic>> enemyHand,
    required int maxEnergy,
  }) {
    final Map<String, List<Map<String, dynamic>>> assignments = {};
    int spent = 0;
    final List<Map<String, dynamic>> playedCards = [];
    final List<Map<String, dynamic>> handCopy = List.from(enemyHand);

    for (final enemy in enemies) {
      if (!enemy.isAlive) continue;
      assignments[enemy.id] = [];

      bool isSilenced = enemy.effects.any((e) => e.type == 'silencio');
      bool wantsDefense = (enemy.hp < enemy.maxHp * 0.3) && (_rng.nextDouble() < 0.6);
      
      List<Map<String, dynamic>> affordable = handCopy.where((c) {
         if (isSilenced && (c['type']?.toString().toLowerCase() == 'magic')) return false;
         return ((c['cost'] ?? 0) as num).toInt() <= (maxEnergy - spent);
      }).toList();
      
      if (affordable.isEmpty) break; // Sin energía o sin cartas en mano para jugar

      List<Map<String, dynamic>> filtered = affordable.where((c) {
        final t = c['type']?.toString().toLowerCase() ?? '';
        if (wantsDefense) return t == 'defense' || t == 'defensa' || t == 'magic';
        return t == 'attack' || t == 'ataque';
      }).toList();

      if (filtered.isEmpty) filtered = affordable;

      final cardToPlay = filtered[_rng.nextInt(filtered.length)];
      assignments[enemy.id]!.add(cardToPlay);
      playedCards.add(cardToPlay);
      handCopy.remove(cardToPlay);
      spent += ((cardToPlay['cost'] ?? 0) as num).toInt();
    }

    return EnemyTurnDecision(
      assignments: assignments,
      energySpent: spent,
      discardedCards: playedCards,
    );
  }

  // ============== HELPERS ============== //

  /// Encuentra un objetivo válido según la formación del atacante.
  Fighter? _findValidTargetByFormation(Fighter attacker, List<Fighter> opponents) {
    final int range = formationRange(attacker.formation);
    final alive = opponents.where((o) => o.isAlive).toList();
    if (alive.isEmpty) return null;

    alive.sort((a, b) => formationDepth(a.formation).compareTo(formationDepth(b.formation)));

    int frontLine = formationDepth(alive.first.formation);

    for (final target in alive) {
      final int targetDepth = formationDepth(target.formation);
      if (targetDepth <= range || targetDepth == frontLine) {
        return target;
      }
    }

    return alive.first;
  }

  /// Verifica si hay suficiente energía para jugar una carta.
  bool canPlayCard(Map<String, dynamic> card, int currentEnergy) {
    final cost = ((card['cost'] ?? 0) as num).toInt();
    return currentEnergy >= cost;
  }
}
