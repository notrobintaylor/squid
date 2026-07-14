// see README.md

Engine_Squid : CroneEngine {

	var sr;
	var inputBus;
	var slotPlayBus;
	var slotBus;
	var slotGain;
	var playGroup;
	var slotBufs;
	var slotFx;
	var recFrames;
	var inputSynth;
	var outputSynth;
	var attack;
	var decay;
	var resampleAmt;

	// ---- EFFECT DISPATCH ----
	prPlay { |slot, bandIdx, panIdx|
		var frames = recFrames[slot];
		var fx = slotFx[slot];
		var buf = slotBufs[slot].bufnum;
		var out = slotBus[slot].index;
		var len = frames / sr;
		// 3-band x 5-pan scatter; band/pan chosen in Lua, passed as 0-based index
		var bands = [[20, 499], [500, 1999], [2000, 9999]];
		var pans = [-1.0, -0.5, 0.0, 0.5, 1.0];
		var band = bands[bandIdx];
		var spatial = [\bandLo, band[0], \bandHi, band[1], \pan, pans[panIdx], \atk, attack, \dcy, decay];
		if(frames <= 0, { ^nil });
		switch(fx,
			1, { Synth(\squid_play_pitch, [\buf, buf, \out, out, \pitchRatio, 0.5, \dur, len] ++ spatial, playGroup, \addToHead); },
			2, { Synth(\squid_play_pitch, [\buf, buf, \out, out, \pitchRatio, 2.0, \dur, len] ++ spatial, playGroup, \addToHead); },
			3, { Synth(\squid_play_rate,  [\buf, buf, \out, out, \rate, 0.5,  \startPos, 0, \dur, len / 0.5] ++ spatial, playGroup, \addToHead); },
			4, { Synth(\squid_play_rate,  [\buf, buf, \out, out, \rate, 2.0,  \startPos, 0, \dur, len / 2.0] ++ spatial, playGroup, \addToHead); },
			5, { Synth(\squid_play_rate,  [\buf, buf, \out, out, \rate, 1.0,  \startPos, 0, \dur, len] ++ spatial, playGroup, \addToHead); },
			6, { Synth(\squid_play_rate,  [\buf, buf, \out, out, \rate, -1.0, \startPos, frames - 1, \dur, len] ++ spatial, playGroup, \addToHead); },
			7, { Synth(\squid_play_hpf,   [\buf, buf, \out, out, \freq, 250, \dur, len] ++ spatial, playGroup, \addToHead); },
			8, { Synth(\squid_play_lpf,   [\buf, buf, \out, out, \freq, 250, \dur, len] ++ spatial, playGroup, \addToHead); }
		);
	}

	alloc {
		var voicePost, ampEnv;

		sr = context.server.sampleRate;

		// ---- BUSES ----
		inputBus = Bus.audio(context.server, 2);
		slotPlayBus = Bus.audio(context.server, 2);
		slotBus = Array.fill(8, { Bus.audio(context.server, 2) });

		// ---- BUFFERS / STATE ----
		slotBufs = Array.fill(8, { Buffer.alloc(context.server, (sr * 8).asInteger, 2) });
		slotFx = Array.fill(8, 5);
		recFrames = Array.fill(8, 0);
		attack = 0;
		decay = 0;
		resampleAmt = 0;

		// ---- SPATIAL SCATTER ----
		voicePost = { |sig, bandLo, bandHi, pan|
			var banded = LPF.ar(HPF.ar(sig, bandLo), bandHi);
			Balance2.ar(banded[0], banded[1], pan);
		};

		// ---- AMP ENVELOPE ----
		ampEnv = { |atk, dcy, dur|
			var atkT = atk * dur;
			var dcyT = dcy * dur;
			var k = dur / max(atkT + dcyT, dur);
			EnvGen.kr(Env.linen(atkT * k, dur - ((atkT + dcyT) * k), dcyT * k), doneAction: 2);
		};

		// ---- SYNTHDEFS ----
		SynthDef(\squid_input, { |inL = 0, inR = 1, out = 0|
			Out.ar(out, [In.ar(inL, 1), In.ar(inR, 1)]);
		}).add;

		SynthDef(\squid_output, { |slotIn = 0, out = 0, amp = 0.5, crunch = 25|
			var chip = In.ar(slotIn, 2);
			// ---- CHIP DSP ----
			var c = crunch.clip(0, 100);
			var sr = c.linexp(0, 100, 24000, 4500);
			var step = c.linlin(0, 100, 0.00001, 0.05);
			var noiseAmt = step * c.linlin(0, 100, 0.0, 0.08);
			var sig;
			chip = Latch.ar(chip, Impulse.ar(sr));
			chip = (chip / step).round(1.0) * step;
			chip = chip + (LFNoise0.ar(8000) * noiseAmt);
			sig = chip * amp;
			Out.ar(out, sig);
			// ---- FX MOD SEND BUSES ----
			if(~sendA.notNil) { Out.ar(~sendA, sig) };
			if(~sendB.notNil) { Out.ar(~sendB, sig) };
		}).add;

		SynthDef(\squid_rec, { |buf = 0, in = 0, dur = 1, preLevel = 0, fbIn = 0, fbAmt = 0|
			var sig = In.ar(in, 2) + (InFeedback.ar(fbIn, 2) * fbAmt);
			EnvGen.kr(Env.linen(0, dur, 0), doneAction: 2);
			RecordBuf.ar(sig, buf, 0, 1, preLevel, run: 1, loop: 0, doneAction: 0);
		}).add;

		SynthDef(\squid_play_rate, { |buf = 0, out = 0, rate = 1, startPos = 0, amp = 1, dur = 1, bandLo = 20, bandHi = 20000, pan = 0, atk = 0, dcy = 0|
			var sig = PlayBuf.ar(2, buf, rate, startPos: startPos, loop: 0);
			Out.ar(out, voicePost.(sig, bandLo, bandHi, pan) * ampEnv.(atk, dcy, dur) * amp);
		}).add;

		SynthDef(\squid_play_pitch, { |buf = 0, out = 0, pitchRatio = 1, amp = 1, dur = 1, bandLo = 20, bandHi = 20000, pan = 0, atk = 0, dcy = 0|
			var sig = PitchShift.ar(PlayBuf.ar(2, buf, 1, startPos: 0, loop: 0), 0.1, pitchRatio, 0, 0);
			Out.ar(out, voicePost.(sig, bandLo, bandHi, pan) * ampEnv.(atk, dcy, dur) * amp);
		}).add;

		SynthDef(\squid_play_hpf, { |buf = 0, out = 0, freq = 250, amp = 1, dur = 1, bandLo = 20, bandHi = 20000, pan = 0, atk = 0, dcy = 0|
			var sig = HPF.ar(PlayBuf.ar(2, buf, 1, startPos: 0, loop: 0), freq);
			Out.ar(out, voicePost.(sig, bandLo, bandHi, pan) * ampEnv.(atk, dcy, dur) * amp);
		}).add;

		SynthDef(\squid_play_lpf, { |buf = 0, out = 0, freq = 250, amp = 1, dur = 1, bandLo = 20, bandHi = 20000, pan = 0, atk = 0, dcy = 0|
			var sig = LPF.ar(PlayBuf.ar(2, buf, 1, startPos: 0, loop: 0), freq);
			Out.ar(out, voicePost.(sig, bandLo, bandHi, pan) * ampEnv.(atk, dcy, dur) * amp);
		}).add;

		// per-slot gain stage: level/mute applied here (Lag = clickless)
		SynthDef(\squid_slotgain, { |in = 0, out = 0, amp = 1|
			Out.ar(out, In.ar(in, 2) * Lag.kr(amp, 0.02));
		}).add;

		context.server.sync;

		slotBufs.do { |b, i|
			("squid buf " ++ i ++ ": " ++ b.numFrames ++ " frames, " ++ b.numChannels ++ " ch").postln;
		};

		// ---- SYNTHS ----  order: input -> plays -> gains -> output
		inputSynth = Synth.head(context.xg, \squid_input, [
			\inL, context.in_b[0].index,
			\inR, context.in_b[1].index,
			\out, inputBus.index
		]);

		playGroup = Group.tail(context.xg);

		slotGain = Array.fill(8, { |i|
			Synth.tail(context.xg, \squid_slotgain, [
				\in, slotBus[i].index, \out, slotPlayBus.index, \amp, 1
			]);
		});

		outputSynth = Synth.tail(context.xg, \squid_output, [
			\slotIn, slotPlayBus.index,
			\out, context.out_b.index
		]);

		// ---- COMMANDS ----
		this.addCommand(\output, "f", { |msg|
			outputSynth.set(\amp, msg[1]);
		});

		this.addCommand(\slot_amp, "if", { |msg|
			slotGain[msg[1]].set(\amp, msg[2]);
		});

		this.addCommand(\crunch, "f", { |msg|
			outputSynth.set(\crunch, msg[1]);
		});

		this.addCommand(\attack, "f", { |msg|
			attack = msg[1];
		});

		this.addCommand(\decay, "f", { |msg|
			decay = msg[1];
		});

		this.addCommand(\resample, "f", { |msg|
			resampleAmt = msg[1];
		});

		this.addCommand(\set_effect, "ii", { |msg|
			slotFx[msg[1]] = msg[2];
		});

		this.addCommand(\rec, "if", { |msg|
			Synth(\squid_rec, [
				\buf, slotBufs[msg[1]].bufnum, \in, inputBus.index, \dur, msg[2], \preLevel, 0,
				\fbIn, slotPlayBus.index, \fbAmt, resampleAmt
			], inputSynth, \addAfter);
			recFrames[msg[1]] = min((msg[2] * sr).asInteger, slotBufs[msg[1]].numFrames);
		});

		this.addCommand(\dub, "if", { |msg|
			Synth(\squid_rec, [
				\buf, slotBufs[msg[1]].bufnum, \in, inputBus.index, \dur, msg[2], \preLevel, 1,
				\fbIn, slotPlayBus.index, \fbAmt, resampleAmt
			], inputSynth, \addAfter);
			recFrames[msg[1]] = min((msg[2] * sr).asInteger, slotBufs[msg[1]].numFrames);
		});

		this.addCommand(\play, "iii", { |msg|
			this.prPlay(msg[1], msg[2], msg[3]);
		});

		this.addCommand(\clear_all, "", { |msg|
			slotBufs.do(_.zero);
			recFrames = Array.fill(8, 0);
		});
	}

	free {
		inputSynth.free;
		outputSynth.free;
		slotGain.do(_.free);
		playGroup.free;
		inputBus.free;
		slotPlayBus.free;
		slotBus.do(_.free);
		slotBufs.do(_.free);
	}
}
