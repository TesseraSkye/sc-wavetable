// Run each of these blocks once. Should just work. CCs for params are 1, 2, 3.
// Takes 3 wavetables up to 256 tables in length. Each frame should be 2048 samples long,
// which is the default for serum wavetables.
// All 3 wt slots should be filled, but they can all be the same.


//made by Tessera Skye. Hit me up if you want to give advice or find bugs or whatever <3
s.boot;

//RUN THIS
(
fork {
	//ignore, don't touch
	~wtPath = ["","",""];



	// C H A N G E   T H E S E ///


	// THESE ARE YOUR WAVETABLES
	//Format these with forward slashes "/", NOT BACK SLASHES "\"
	~wtPath.put(0,"YOUR PATH HERE");
	~wtPath.put(1,"YOUR PATH HERE");
	~wtPath.put(2,"YOUR PATH HERE");



	~maxVoices = 8;




	// v v v  D O N ' T   T O U C H  v v v //


	~activeSynth = \wavetable;

	// W A V E T A B L E

	//makes wavetable out of buffer
	(
		~buildWavetable = {
			arg srcBuf, newBuf, tableNum, frameSize;
			var floatArr, sig, frameOffset, outBuff;

			// build frame offset from
			frameOffset = ((tableNum * frameSize)-2).clip(0,255*frameSize);
			//builds float array from buffer
			srcBuf.getToFloatArray(frameOffset, frameSize, action:{arg floatArr; {

				//converts float array to signal
				sig = Signal.newClear(frameSize).waveFill({ arg x, old, i;
					//This is kind of a lowpass filter?? It removes some weird aliasing
					if(x+20<frameSize,if(x>20,floatArr[x],floatArr[x+20]),floatArr[x-20]);
				},0,frameSize);
				//to wavetable format
				sig = sig.asWavetable;

				// send collection streams an array (this time it's a signal) to the server and into a buffer.
				newBuf.sendCollection(sig, wait:0.01);

				//free the signal and array
				floatArr.free;
				sig.free;
			}.defer;});
			newBuf;
		};
		"Registered Wavetable Build Function...".postln;
	);


	// Wavetable Prep

	(
		//forked so delays work
		fork {
			"".postln;
			~frameSize = 2048;
			~tables = [];
			~wtRef = [];
			~tableFrames = [];
			~tableSamps = [];



			~wtPath.do{
				arg item, index;
				var loopDone, activeTableSamps, activeFrames, activeRef;
				~wtRef = ~wtRef.add(Buffer.read(s, ~wtPath[index],bufnum:1000+index));
				loopDone = Condition(false);
				fork{
					0.1.wait;
					"Calculating Frames...".postln;
					activeRef = ~wtRef[index];
					// activeRef.postln;
					~tableSamps = ~tableSamps.add(activeRef.numFrames);
					// ~tableSamps.postln;
					activeTableSamps = ~tableSamps[index];
					// activeTableSamps
					// activeTableSamps.postln;
					~tableFrames = ~tableFrames.add(activeTableSamps / ~frameSize);
					// ~tableFrames.postln;
					activeFrames = ~tableFrames[index];
					activeFrames.postln;
					"".postln;
					0.1.wait;
					("Wavetable build started for table" + (index+1)).postln;
					//get frames in wavetable
					~tables = ~tables.add(Buffer.allocConsecutive(activeFrames,s,~frameSize*2,bufnum:index*256););
					"".postln;
					0.1.wait;
					fork {
						~tables[index].do({
							arg data, num;
							// num.postln;
							// done twice to fix weird bug
							fork {
								//forces the execution to wait so there aren't overlaps
								(num/5).wait;
								AppClock.sched(0, {(~buildWavetable.value(~wtRef[index], data, num, ~frameSize));});
								AppClock.sched(0.05, {~tables[index] = ~tables[index].put(num,~buildWavetable.value(~wtRef[index], data, num, ~frameSize);)});
								("Built table" + (num+1)).postln;
								(num+1 == ~tableFrames[index]).if({("___Table"+(index+1)+"Done!___").postln},{});
							};
						});
						// loopDone.unhang.wait(~tableFrames[index]*0.5 + 1);
					};
					loopDone.hang;
				};

			};
		};
	);

	1.wait;
		((~tableFrames.maxItem) / 5).wait;

	(
		SynthDef.new(\wavetable, {
			arg rate=0, cpsPitch=110, frameSize = 2048, paramX=0, paramY=0, paramZ=0, frameCount = [1,1,1];
			var sig1, sig2, sig3, array, levels, out;
			frameCount = frameCount - 1;

			paramX = LinExp.kr(paramX)-1;

			// Uses HSV to RGB to make an even power mixer
			levels = levels.add(1-((1*paramY) * ArrayMax.kr([0,ArrayMin.kr([((5 + (6*paramX))%6),4-(((5 + (6*paramX))%6)),1])])));
			levels = levels.add(1-((1*paramY) * ArrayMax.kr([0,ArrayMin.kr([((3 + (6*paramX))%6),4-(((3 + (6*paramX))%6)),1])])));
			levels = levels.add(1-((1*paramY) * ArrayMax.kr([0,ArrayMin.kr([((1 + (6*paramX))%6),4-(((1 + (6*paramX))%6)),1])])));


			// 3 sets of wavetables
			sig1 = VOsc.ar((paramZ * (~tableFrames[0]-1)).clip(0.001,(~tableFrames[0]-1)-0.001),cpsPitch,0,levels[0][0][0]);
			sig2 = VOsc.ar(256+(paramZ * (~tableFrames[1]-1)).clip(0.001,(~tableFrames[1]-1)-0.001),cpsPitch,levels[1][0][0]);
			sig3 = VOsc.ar(512+(paramZ * (~tableFrames[2]-1)).clip(0.001,(~tableFrames[2]-1)-0.001),cpsPitch,0,levels[2][0][0]);
			//combine them
			array = [sig1 , sig2, sig3];
			//remove any DC offset
			// array = LeakDC.ar(array);
			//sum them
			//reduced and normalized to prevent clipping
			out = Mix(array);
			out = Normalizer.ar(out) *0.2;
			Out.ar(0, [out,out]);
		}).add;
	);


	//  M I D I

	MIDIClient.init(nil,nil,false);
	MIDIIn.connectAll(false);
	0.5.wait;
	(
		MIDIdef.noteOn(\keybedOn, {
			arg val, note, chan, src;

			//Round robin steal voices n such
			//If it would be too many...
			if(((~voiceAge.size+1) > 8),{
				var ageMinIndex;
				ageMinIndex = ~voiceAge.minIndex;
				ageMinIndex.postln;
				//Free old synth..
				~voiceArray[ageMinIndex].free;
				//overwrite the oldest..
				~voiceArray.put(ageMinIndex,Synth(~activeSynth,[\cpsPitch, note.midicps, \paramX, ~paramArray[0],\paramY, ~paramArray[1], \paramZ, ~paramArray[2]]));
				//overwrite the note number..
				~voiceNote.put(ageMinIndex, note);
				//... and overwrite the date object.
				~voiceAge.put(ageMinIndex, Date.getDate.rawSeconds);
			},
			{
				//add them nondestructively
				~voiceArray = ~voiceArray.add(Synth(~activeSynth,
					[\cpsPitch, note.midicps, \paramX, ~paramArray[0],\paramY, ~paramArray[1], \paramZ, ~paramArray[2]]));
				~voiceAge = ~voiceAge.add(Date.getDate.rawSeconds);
				~voiceNote = ~voiceNote.add(note);
			});
		}).permanent_(true);

		MIDIdef.noteOff(\keybedOff, {
			arg val, note, chan, src;
			var index;

			//get freeing note
			index = ~voiceNote.indexOf(note);
			// if it exists, remove it. if not, assume it was freed
			if((index+2).booleanValue,{
				//Free synth..
				~voiceArray[index].free;
				//then remove it..
				~voiceArray.removeAt(index);
				//then overwrite the date object...
				~voiceAge.removeAt(index);
				//..then remove the note data.
				~voiceNote.removeAt(index);
			})
		}).permanent_(true);

		//CCs
		~paramArray=[0,0,0];
		MIDIdef.cc(\paramX,{
			arg val, num, chan, src;
			var newVal;
			newVal=(val/127);
			~paramArray = ~paramArray.put(0,newVal);
			~voiceArray.do({
				arg item, index;
				item.set(\paramX, newVal);
			});
		},1).permanent_(true);

		MIDIdef.cc(\paramY,{
			arg val, num, chan, src;
			var newVal;
			newVal=(val/127);
			~paramArray = ~paramArray.put(1,newVal);
			~voiceArray.do({
				arg item, index;
				item.set(\paramY, newVal);
			});
		},2).permanent_(true);

		MIDIdef.cc(\paramZ,{
			arg val, num, chan, src;
			var newVal;
			newVal=(val/127);
			~paramArray = ~paramArray.put(2,newVal);
			~voiceArray.do({
				arg item, index;
				item.set(\paramZ, newVal);
			});
		},3).permanent_(true);
	);

};
);