function main()
    %פונקציה ראשית
    [audio, rate, name] = load_audio();
    [windows, winData] = windowing(audio, rate);
    [vad, vadTime] = compute_vad(windows, rate, winData);
    [spec, freqs, times, pitchVals] = compute_pitch_spectrogram(audio, rate, winData);
    synth = synthesize_audio(audio, rate, pitchVals, vad, winData);
    enhanced_audio = enhance_speech(audio, rate, winData); % סעיף הבונוס
    plot_results(audio, rate, vad, vadTime, spec, freqs, times, pitchVals, synth, enhanced_audio);
    export_results(vadTime, vad, times, pitchVals, synth, enhanced_audio, rate, name);
end

function [audio, rate, name] = load_audio()
    % טעינת קובץ אודיו
    [name, path] = uigetfile({'*.wav;*.mp3', 'Audio Files (*.wav, *.mp3)'}, 'בחר קובץ אודיו');
    if isequal(name, 0)
        error('לא נבחר קובץ.');
    end
    [audio, rate] = audioread(fullfile(path, name));
end

function [windows, winData] = windowing(audio, rate)
    % חלוקת האות לחלונות
    winSec = 0.03;
    winSize = round(winSec * rate);
    overlap = round(0.25 * winSize);
    step = winSize - overlap;

    numWins = floor((length(audio) - overlap) / step);
    windows = zeros(winSize, numWins);

    for i = 1:numWins
        start = (i - 1) * step + 1;
        endIdx = min(start + winSize - 1, length(audio));
        winData = audio(start:endIdx) .* hamming(length(start:endIdx));
        windows(1:length(winData), i) = winData;
    end

    winData = struct('winSize', winSize, 'overlap', overlap, 'step', step);
end

function [vad, vadTime] = compute_vad(windows, rate, winData)
    % חישוב RMS וזיהוי פעילות קולית
    rmsVals = sqrt(mean(windows.^2, 1));
    thresh = 0.3 * mean(rmsVals);
    vad = rmsVals > thresh;
    vadTime = (0:length(vad)-1) * (winData.step / rate);
end

function [spec, freqs, times, pitchVals] = compute_pitch_spectrogram(audio, rate, winData)
    % חישוב ספקטרוגרמה ופיץ'
    [spec, freqs, times] = stft(audio, rate, 'Window', hamming(winData.winSize), 'OverlapLength', winData.overlap);
    pitchVals = pitch(audio, rate, 'WindowLength', winData.winSize, 'OverlapLength', winData.overlap, 'Range', [50, 500]);
end

function synth = synthesize_audio(audio, rate, pitchVals, vad, winData)
    % יצירת אות סינתטי
    synth = zeros(length(audio), 1);
    numWins = length(vad);

    for i = 1:numWins
        if vad(i)
            basePitch = pitchVals(i);
            if isnan(basePitch), continue; end

            harmonics = basePitch * (1:5);
            harmonics(harmonics > rate/2) = [];
            spectrum = zeros(winData.winSize, 1);

            for h = harmonics
                bin = round(h / (rate / winData.winSize)) + 1;
                if bin <= winData.winSize
                    spectrum(bin) = 1;
                end
            end

            synthWin = real(ifft(spectrum, 'symmetric'));
            start = (i - 1) * winData.step + 1;
            endIdx = min(start + winData.winSize - 1, length(audio));
            synth(start:endIdx) = synth(start:endIdx) + synthWin(1:(endIdx - start + 1));
        end
    end
end

function enhanced_audio = enhance_speech(audio, rate, winData)
    % סעיף הבונוס: שיפור דיבור עם הוספת רעש ורוד והסרתו
    pink_noise = dsp.ColoredNoise('Color','pink','SamplesPerFrame',length(audio));
    noisy_audio = audio + 0.05 * pink_noise(); % הוספת רעש ורוד

    % FFT של האות עם רעש
    noisy_spectrum = fft(noisy_audio);
    clean_spectrum = abs(noisy_spectrum) - mean(abs(noisy_spectrum)); % חיסור ספקטרום רעש ממוצע
    clean_spectrum(clean_spectrum < 0) = 0; % מניעת ערכים שליליים

    % IFFT לשחזור האות המשופר
    enhanced_audio = real(ifft(clean_spectrum .* exp(1j * angle(noisy_spectrum))));
end

function plot_results(audio, rate, vad, vadTime, spec, freqs, times, pitchVals, synth, enhanced_audio)
    % הצגת תוצאות
    figure;

    subplot(5,1,1);
    plot((0:length(audio)-1)/rate, audio);
    title('Original Audio'); xlabel('Time (s)'); ylabel('Amplitude');

    subplot(5,1,2);
    plot((0:length(synth)-1)/rate, synth);
    title('Synthesized Audio'); xlabel('Time (s)'); ylabel('Amplitude');

    subplot(5,1,3);
    plot((0:length(enhanced_audio)-1)/rate, enhanced_audio);
    title('Enhanced Speech (After Noise Reduction)'); xlabel('Time (s)'); ylabel('Amplitude');

    subplot(5,1,4);
    imagesc(times, freqs(freqs >= 0), mag2db(abs(spec(freqs >= 0, :))));
    axis xy; colormap jet; colorbar; title('Spectrogram');

    subplot(5,1,5);
    plot(times(1:length(pitchVals)), pitchVals, 'g'); hold on;
    plot(times(1:length(pitchVals)), pitchVals / 2, 'b');
    title('Pitch Contour'); xlabel('Time (s)'); ylabel('Frequency (Hz)');
end

function export_results(vadTime, vad, times, pitchVals, synth, enhanced_audio, rate, name)
    % ייצוא תוצאות
    audiowrite([name '_synth.wav'], synth, rate);
    audiowrite([name '_enhanced.wav'], enhanced_audio, rate);
    writetable(table(vadTime', vad', 'VariableNames', {'Time', 'VAD'}), [name '_vad.csv']);
    writetable(table(times', pitchVals(1:length(times))', 'VariableNames', {'Time', 'PitchFrequency'}), [name '_pitch.csv']);
    fprintf('תוצאות נשמרו: %s_synth.wav, %s_enhanced.wav, %s_vad.csv, %s_pitch.csv\n', name, name, name, name);
end
