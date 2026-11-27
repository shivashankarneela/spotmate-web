import 'dart:async';
import 'package:flutter/material.dart';

/// The 20 user-supplied HaloBerry characters. Every pose is an independent,
/// transparent WebP, never a segment of the old character sprite sheet.
class HaloCharacter {
  const HaloCharacter(this.name, this.assetPrefix, this.poses);
  final String name;
  final String assetPrefix;
  final List<String> poses;
}

class HaloAvatarCatalog {
  static const Map<String, HaloCharacter> characters = {
    'boy_01': HaloCharacter('arjun', 'boy_01_arjun', const ['01_victory_jump', '02_headphone_groove', '03_sprint_dash', '04_gaming_focus', '05_friendly_wave']),
    'boy_02': HaloCharacter('kabir', 'boy_02_kabir', const ['01_ollie_jump', '02_kick_push', '03_board_flip', '04_cool_salute', '05_celebration_jump']),
    'boy_03': HaloCharacter('rohan', 'boy_03_rohan', const ['01_eureka_point', '02_glasses_adjust', '03_tablet_walk', '04_double_thumbs', '05_coffee_cheers']),
    'boy_04': HaloCharacter('dev', 'boy_04_dev', const ['01_bboy_freeze', '02_moonwalk_tip', '03_star_jump', '04_mic_drop', '05_hype_clap']),
    'boy_05': HaloCharacter('vikram', 'boy_05_vikram', const ['01_collar_pop', '02_helmet_wave', '03_fist_bump', '04_arms_crossed', '05_fist_pump']),
    'boy_06': HaloCharacter('aditya', 'boy_06_aditya', const ['01_rock_jump', '02_shoulder_walk', '03_serenade_kneel', '04_snap_groove', '05_stage_bow']),
    'boy_07': HaloCharacter('siddharth', 'boy_07_siddharth', const ['01_finish_sprint', '02_lunge_stretch', '03_hydration_sip', '04_sprint_crouch', '05_bicep_flex']),
    'boy_08': HaloCharacter('neel', 'boy_08_neel', const ['01_bhangra_dance', '02_jacket_button', '03_sparkler_joy', '04_open_welcome', '05_festive_clap']),
    'boy_09': HaloCharacter('ishan', 'boy_09_ishan', const ['01_viewfinder_snap', '02_low_angle_kneel', '03_camera_review', '04_thumbs_up_strap', '05_friendly_wave']),
    'boy_10': HaloCharacter('aryan', 'boy_10_aryan', const ['01_slam_dunk_leap', '02_crossover_dribble', '03_jump_shot', '04_trick_pass', '05_hoops_wave']),
    'girl_01': HaloCharacter('ananya', 'girl_01_ananya', const ['01_finger_hearts', '02_selfie_snap', '03_street_groove', '04_hair_flip', '05_cheer_hop']),
    'girl_02': HaloCharacter('meera', 'girl_02_meera', const ['01_garba_spin', '02_warm_namaste', '03_festive_leap', '04_diya_lamp', '05_poised_wave']),
    'girl_03': HaloCharacter('zoya', 'girl_03_zoya', const ['01_paint_lunge', '02_hand_frame', '03_beret_tip', '04_joyful_skip', '05_proud_stance']),
    'girl_04': HaloCharacter('kavya', 'girl_04_kavya', const ['01_reading_walk', '02_book_hop', '03_cozy_tea', '04_cheerful_peace', '05_book_peek']),
    'girl_05': HaloCharacter('riya', 'girl_05_riya', const ['01_high_note_leap', '02_sassy_wink', '03_crowd_point', '04_rock_horns', '05_flying_kiss']),
    'girl_06': HaloCharacter('tara', 'girl_06_tara', const ['01_jump_serve', '02_forehand_swing', '03_victory_fist', '04_ball_balance', '05_match_wave']),
    'girl_07': HaloCharacter('diya', 'girl_07_diya', const ['01_boho_twirl', '02_wildflower', '03_horizon_point', '04_heart_gratitude', '05_summer_skip']),
    'girl_08': HaloCharacter('nisha', 'girl_08_nisha', const ['01_dj_scratch', '02_parkour_leap', '03_hologram_tap', '04_neon_peace', '05_bass_drop_hype']),
    'girl_09': HaloCharacter('priya', 'girl_09_priya', const ['01_kathak_spin', '02_graceful_swirl', '03_pranam_greeting', '04_aramandi_mudra', '05_jasmine_offering']),
    'girl_10': HaloCharacter('sana', 'girl_10_sana', const ['01_coffee_toast', '02_text_laugh', '03_city_wave', '04_fashion_stance', '05_good_news_cheer']),
  };
  static String filename(String id, int pose) {
    final character = characters[id] ?? characters['boy_01']!;
    final index = pose.clamp(0, character.poses.length - 1);
    return 'assets/avatars/postures/${character.assetPrefix}_${character.poses[index]}.webp';
  }
}

/// Stationary by default. Auto mode changes the *pose only* every 30 seconds.
/// The identity remains the same, and thumbnail avatars never run timers.
class HaloIllustratedAvatar extends StatefulWidget {
  const HaloIllustratedAvatar({
    super.key, required this.avatarId, required this.size,
    required this.fullPortrait, required this.fallback,
    this.postureIndex = 0, this.autoChangePosture = false,
  });
  final String avatarId;
  final double size;
  final bool fullPortrait;
  final Widget fallback;
  final int postureIndex;
  final bool autoChangePosture;

  @override
  State<HaloIllustratedAvatar> createState() => _HaloIllustratedAvatarState();
}

class _HaloIllustratedAvatarState extends State<HaloIllustratedAvatar> {
  Timer? _timer;
  int _currentPose = 0;
  @override
  void initState() {
    super.initState();
    _currentPose = widget.postureIndex.clamp(0, 4);
    _configureTimer();
  }
  @override
  void didUpdateWidget(covariant HaloIllustratedAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarId != widget.avatarId ||
        oldWidget.postureIndex != widget.postureIndex ||
        oldWidget.autoChangePosture != widget.autoChangePosture ||
        oldWidget.fullPortrait != widget.fullPortrait) {
      _currentPose = widget.postureIndex.clamp(0, 4);
      _configureTimer();
    }
  }
  void _configureTimer() {
    _timer?.cancel();
    if (!widget.fullPortrait || !widget.autoChangePosture) return;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _currentPose = (_currentPose + 1) % 5);
    });
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final full = widget.fullPortrait;
    final dimension = widget.size;
    final character = HaloAvatarCatalog.characters[widget.avatarId] ??
        HaloAvatarCatalog.characters['boy_01']!;
    // The cleaned archive installs defaults by stable character ID.
    final defaultFile =
        'assets/avatars/default/${widget.avatarId}.webp';
    Widget defaultImage() => Image.asset(
      defaultFile,
      width: dimension, height: dimension,
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => widget.fallback,
    );
    // Display the original submitted character artwork as the permanent
    // default. Other poses use the 100-posture collection if installed,
    // otherwise fall back to the same original illustration.
    final image = _currentPose == 0
        ? defaultImage()
        : Image.asset(
            HaloAvatarCatalog.filename(widget.avatarId, _currentPose),
            key: ValueKey('${widget.avatarId}-$_currentPose'),
            width: dimension, height: dimension,
            fit: BoxFit.contain,
            alignment: Alignment.bottomCenter,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => defaultImage(),
          );
    // The character's real alpha outline is the border: no white panel,
    // sticker stroke, rectangular clipping, or painted avatar background.
    // A soft ground shadow visually anchors the feet to any room wallpaper.
    return SizedBox.square(
      dimension: dimension,
      child: Stack(fit: StackFit.expand, children: [
        if (full)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: dimension * .43,
              height: dimension * .045,
              margin: EdgeInsets.only(bottom: dimension * .008),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(dimension),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x300D2723),
                    blurRadius: 17,
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        AnimatedSwitcher(
          duration: widget.autoChangePosture && full
              ? const Duration(milliseconds: 280)
              : Duration.zero,
          child: full
              ? Padding(
                  key: ValueKey('full-${widget.avatarId}-$_currentPose'),
                  padding: EdgeInsets.fromLTRB(
                    dimension * .035, dimension * .025,
                    dimension * .035, 0,
                  ),
                  child: Align(alignment: Alignment.bottomCenter, child: image),
                )
              : ClipOval(
                  key: ValueKey('small-${widget.avatarId}-$_currentPose'),
                  child: Transform.scale(
                    scale: 2.0,
                    alignment: const Alignment(0, -.78),
                    child: image,
                  ),
                ),
        ),
      ]),
    );
  }
}
