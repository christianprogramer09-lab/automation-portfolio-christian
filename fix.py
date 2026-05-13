import re

with open("lib/screens/editor/level_editor_screen.dart", "r", encoding="utf-8") as f:
    text = f.read()

# Replace UI
pattern = r"          // Capa de UI.*?  \}\n\}\n\n/// ============================================================\n/// LevelEditorGame"
new_ui = """          // Capa de UI
          if (!_isPanelVisible)
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.settings),
                    label: const Text('ABRIR EDITOR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KColors.cyanAccent,
                      foregroundColor: Colors.black,
                      elevation: 8,
                    ),
                    onPressed: () => setState(() => _isPanelVisible = true),
                  ),
                ),
              ),
            ),
            
          if (_isPanelVisible)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  height: MediaQuery.of(context).size.height * 0.55,
                  margin: const EdgeInsets.all(8.0),
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    border: Border.all(color: KColors.cyanAccent),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'EDITOR DE NIVELES',
                            style: TextStyle(
                              color: KColors.cyanAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          ElevatedButton.icon(
                             icon: const Icon(Icons.check),
                             label: const Text('LISTO'),
                             style: ElevatedButton.styleFrom(
                               backgroundColor: KColors.gold,
                               foregroundColor: Colors.black,
                             ),
                             onPressed: () => setState(() => _isPanelVisible = false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildColumn1()),
                              const SizedBox(width: 16),
                              Expanded(child: _buildColumn2()),
                              const SizedBox(width: 16),
                              Expanded(child: _buildColumn3()),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildColumn1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Configuración del Nivel',
          style: TextStyle(
            color: KColors.cyanAccent,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Modo del Editor:',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        SegmentedButton<EditorMode>(
          segments: const [
            ButtonSegment(value: EditorMode.libre, label: Text('Libre')),
            ButtonSegment(value: EditorMode.stage1, label: Text('Stage 1')),
            ButtonSegment(value: EditorMode.stage2, label: Text('Stage 2')),
          ],
          selected: {_editorMode},
          onSelectionChanged: (Set<EditorMode> newSelection) {
            _onEditorModeChanged(newSelection.first);
          },
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
              if (states.contains(WidgetState.selected)) {
                return KColors.cyanAccent;
              }
              return Colors.transparent;
            }),
            foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.black;
              }
              return Colors.white;
            }),
          ),
        ),
        if (_editorMode == EditorMode.libre) ...[
          const SizedBox(height: 10),
          const Text(
            'Enemigos (Libre):',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1')),
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
            ],
            selected: {_enemyCount},
            onSelectionChanged: (Set<int> newSelection) {
              _onEditorModeChanged(EditorMode.libre);
              _onEnemyCountChanged(newSelection.first);
            },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) return KColors.cyanAccent;
                return Colors.transparent;
              }),
              foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) return Colors.black;
                return Colors.white;
              }),
            ),
          ),
        ],
        const Divider(color: Colors.white24, height: 20),
        const Text(
          'Posiciones Actuales:',
          style: TextStyle(
            color: KColors.cyanAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...characterPositions.entries.map((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Text(
              '${e.key}: X=${e.value.x.toStringAsFixed(3)}, Y=${e.value.y.toStringAsFixed(3)}',
              style: const TextStyle(color: Colors.white, fontFamily: 'Courier', fontSize: 12),
            ),
          );
        }),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('COPIAR COORDENADAS'),
            style: ElevatedButton.styleFrom(
              backgroundColor: KColors.cyanAccent,
              foregroundColor: Colors.black,
            ),
            onPressed: _copyToClipboard,
          ),
        ),
      ],
    );
  }

  Widget _buildColumn2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Efectos Visuales',
          style: TextStyle(
            color: KColors.cyanAccent,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: Icon(
              _showEffectPreview ? Icons.visibility_off : Icons.flare,
            ),
            label: Text(
              _showEffectPreview ? 'OCULTAR EFECTOS' : 'AÑADIR EFECTOS',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _showEffectPreview ? Colors.redAccent : Colors.purpleAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: _toggleEffect,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Nota:',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Arrastra a los personajes libres o efectos de daño en la pantalla para obtener su posición en el código fuente.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildColumn3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'JUGADOR / APARIENCIA',
          style: TextStyle(
            color: KColors.cyanAccent,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.flip),
            label: const Text('VOLTEAR JUGADOR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => _game.flipPlayer(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildSpawnButton('Arquero', 'personajes/archer_inactivo_01.png'),
            _buildSpawnButton('Boxeador', 'personajes/box_inactivo_01.png'),
            _buildSpawnButton('Berserker', 'personajes/serker_inactivo_01.png'),
            _buildSpawnButton('Peleador', 'personajes/kungfu_inactivo_01.png'),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'ESTADO DE ANIMACIÓN',
          style: TextStyle(
            color: KColors.cyanAccent,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildAnimButton('Inactivo', 'inactivo'),
            _buildAnimButton('Ataque', 'ataque'),
            _buildAnimButton('Daño', 'daño'),
            _buildAnimButton('Buff', 'buff'),
          ],
        ),
      ],
    );
  }
}

/// ============================================================
/// LevelEditorGame"""

if re.search(pattern, text, re.DOTALL):
    text = re.sub(pattern, new_ui, text, flags=re.DOTALL)
    with open("lib/screens/editor/level_editor_screen.dart", "w", encoding="utf-8") as f:
        f.write(text)
    print("REPLACED")
else:
    print("COULD NOT FIND")
