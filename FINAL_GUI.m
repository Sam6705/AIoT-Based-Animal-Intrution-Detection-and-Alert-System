function FINAL_GUI
    %--------------------------------------------------------------
    % Create main figure
    %--------------------------------------------------------------
    hFig = figure('Name', 'Live DashCAM', ...
                  'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'none', ...
                  'Color', [0.95 0.95 0.95], 'Position', [100 50 1250 700], ...
                  'CloseRequestFcn', @closeGUI);

    % Title
    uicontrol('Style', 'text', 'Parent', hFig, 'String', 'Live DashCAM', ...
              'FontSize', 20, 'FontWeight', 'bold', 'FontName', 'Times New Roman', ...
              'ForegroundColor', [0.1 0.1 0.5], 'BackgroundColor', [0.95 0.95 0.95], ...
              'Position', [350 650 550 40]);

    % Main video display
    hAx = axes('Parent', hFig, 'Units', 'pixels', 'Position', [80 150 500 450]);
    axis(hAx, 'off');

    % Detection info (updated to meters)
    hText = uicontrol('Style', 'text', 'Position', [80 90 600 40], 'FontSize', 13, ...
                      'FontName', 'Times New Roman', 'ForegroundColor', 'k', ...
                      'BackgroundColor', [0.95 0.95 0.95], ...
                      'String', 'Detected Object: - | Distance: - m | Risk: -');

    % Warning text
    hWarn = uicontrol('Style', 'text', 'Position', [80 50 600 30], 'FontSize', 13, ...
                      'FontName', 'Times New Roman', 'FontWeight', 'bold', ...
                      'BackgroundColor', [0.95 0.95 0.95], 'ForegroundColor', 'red', ...
                      'String', '', 'Visible', 'off');

    %--------------------------------------------------------------
    % Graph axes (2 graphs) - Updated to meters
    %--------------------------------------------------------------
    ax1 = subplot('Position', [0.62 0.55 0.32 0.18]); % Distance
    ax2 = subplot('Position', [0.62 0.25 0.32 0.18]); % Risk Factor

    titles = {'Distance vs Time (m)', 'Risk Factor vs Time (%)'};
    axs = [ax1, ax2];
    
    for i = 1:2
        title(axs(i), titles{i}, 'FontSize', 12, 'FontWeight', 'bold');
        xlabel(axs(i), 'Frame Number');
        ylabel(axs(i), 'Value');
        grid(axs(i), 'on');
        hold(axs(i), 'on');
        
        % Initialize with empty plots
        if i == 1
            hPlot1 = plot(axs(i), NaN, NaN, 'r-', 'LineWidth', 1.5);
        else
            hPlot2 = plot(axs(i), NaN, NaN, 'b-', 'LineWidth', 1.5);
        end
    end

    % Initialize data buffers
    distData = [];  % Now in meters
    riskData = [];
    tBuffer = [];
    frameIdx = 0;
    maxPoints = 100; % Keep last 100 points for display

    %--------------------------------------------------------------
    % Load YOLOv2
    %--------------------------------------------------------------
    modelName = 'tinyYOLOv2-coco';
    
    % Check if model exists, download if needed
    if ~exist([modelName '.mat'], 'file')
        disp('📥 Downloading pretrained YOLOv2 model...');
        try
            helper.downloadPretrainedYOLOv2(modelName);
        catch
            % Alternative if helper function doesn't exist
            disp('⚠️ Please download the YOLOv2 model manually or check your connection');
            disp('Continuing with assumed model file...');
        end
    end
    
    try
        pretrained = load(modelName);
        detector = pretrained.yolov2Detector;
    catch
        error('Failed to load YOLOv2 detector. Please ensure the model file exists.');
    end

    % Initialize camera
    try
        cam = webcam(1);
    catch
        try
            % Try default camera if camera 1 fails
            cam = webcam;
        catch
            error('No webcam detected. Please connect a camera and try again.');
        end
    end
    
    focalLength = 800; 
    knownWidth = 0.2; % Changed to meters (20 cm = 0.2 m)

    disp('🔹 Live detection with graphs and risk alerts running...');
    disp('🔸 Close the figure window to stop');
    
    %--------------------------------------------------------------
    % Create stop button
    %--------------------------------------------------------------
    uicontrol('Style', 'pushbutton', 'String', 'STOP', ...
              'Position', [600 50 100 30], ...
              'FontSize', 12, 'FontWeight', 'bold', ...
              'BackgroundColor', [1 0.5 0.5], ...
              'Callback', @(~,~) closeGUI(hFig, cam));
    
    %--------------------------------------------------------------
    % Initialize sound variables
    %--------------------------------------------------------------
    % Generate random frequencies for sound (200 Hz to 2000 Hz)
    randomFrequencies = randi([200, 2000], 1, 10);
    currentFreqIndex = 1;
    
    % Audio parameters
    sampleRate = 8192;
    duration = 0.3; % seconds
    t = 0:1/sampleRate:duration;
    
    % Generate random sounds
    soundSignals = {};
    for i = 1:length(randomFrequencies)
        % Create a beep sound with random frequency
        soundSignals{i} = sin(2 * pi * randomFrequencies(i) * t');
        % Apply envelope to avoid clicks
        envelope = linspace(0, 1, length(t)/4)';
        envelope = [envelope; ones(length(t)/2, 1); flip(envelope)];
        if length(envelope) > length(soundSignals{i})
            envelope = envelope(1:length(soundSignals{i}));
        elseif length(envelope) < length(soundSignals{i})
            envelope = [envelope; ones(length(soundSignals{i}) - length(envelope), 1)];
        end
        soundSignals{i} = soundSignals{i} .* envelope;
    end
    
    lastSoundTime = tic;
    soundCooldown = 2; % Minimum seconds between sounds
    soundEnabled = true;
    
    %--------------------------------------------------------------
    % Detection Loop
    %--------------------------------------------------------------
    isRunning = true;
    
    while ishandle(hFig) && isRunning
        frameIdx = frameIdx + 1;
        
        try
            img = snapshot(cam);
        catch
            disp('❌ Camera error!');
            break;
        end
        
        [boxes, scores, labels] = detect(detector, img);

        if ~isempty(boxes)
            % Find highest confidence detection
            [maxScore, idx] = max(scores);
            box = boxes(idx, :);
            
            imgAnnotated = insertObjectAnnotation(img, 'rectangle', box, labels(idx));
            
            % Calculate distance in meters
            boxWidth = box(3);
            distance = (knownWidth * focalLength) / max(boxWidth, 1); % Distance in meters
            
            detectedObject = string(labels(idx));
            
            % Risk Factor calculation (0-100 scale)
            % Risk increases as distance decreases and confidence increases
            % Convert distance to cm for risk calculation to maintain similar sensitivity
            distance_cm = distance * 100;
            baseRisk = max(0, 100 - distance_cm); % Higher risk for closer objects
            riskFactor = min(100, baseRisk * maxScore * 1.5);
            
            % Warning logic based on risk
            if riskFactor > 70
                warningMsg = sprintf('🚨 HIGH RISK! %s at %.2f m | Risk: %.1f%%', ...
                                      detectedObject, distance, riskFactor);
                set(hWarn, 'String', warningMsg, 'Visible', 'on', 'ForegroundColor', 'red');
                set(hText, 'ForegroundColor', 'r');
                
                % Play sound for high risk (random frequency)
                if soundEnabled && toc(lastSoundTime) > soundCooldown
                    % Randomly select a sound signal
                    randomIndex = randi(length(soundSignals));
                    sound(soundSignals{randomIndex}, sampleRate);
                    lastSoundTime = tic;
                    
                    % Occasionally generate new random frequencies
                    if randi(10) > 8 % 20% chance to refresh sounds
                        randomFrequencies = randi([200, 2000], 1, 10);
                        for j = 1:length(randomFrequencies)
                            soundSignals{j} = sin(2 * pi * randomFrequencies(j) * t');
                            % Apply envelope
                            envelope = linspace(0, 1, length(t)/4)';
                            envelope = [envelope; ones(length(t)/2, 1); flip(envelope)];
                            if length(envelope) > length(soundSignals{j})
                                envelope = envelope(1:length(soundSignals{j}));
                            elseif length(envelope) < length(soundSignals{j})
                                envelope = [envelope; ones(length(soundSignals{j}) - length(envelope), 1)];
                            end
                            soundSignals{j} = soundSignals{j} .* envelope;
                        end
                    end
                end
                
            elseif riskFactor > 40
                warningMsg = sprintf('⚠️ Caution: %s at %.2f m | Risk: %.1f%%', ...
                                      detectedObject, distance, riskFactor);
                set(hWarn, 'String', warningMsg, 'Visible', 'on', 'ForegroundColor', [0.9 0.5 0]);
                set(hText, 'ForegroundColor', [0.9 0.5 0]);
                
                % Play occasional sound for medium risk (with lower probability)
                if soundEnabled && toc(lastSoundTime) > soundCooldown && rand() < 0.3
                    randomIndex = randi(length(soundSignals));
                    sound(soundSignals{randomIndex}, sampleRate);
                    lastSoundTime = tic;
                end
                
            else
                set(hWarn, 'Visible', 'off');
                set(hText, 'ForegroundColor', 'k');
            end

            % Update detection info text (now in meters)
            hText.String = sprintf('Detected: %s | Distance: %.2f m | Risk: %.1f%% | Conf: %.2f', ...
                                    detectedObject, distance, riskFactor, maxScore);

            % Update buffers
            distData(end+1) = distance;
            riskData(end+1) = riskFactor;
            tBuffer(end+1) = frameIdx;
            
            % Limit buffer size
            if length(tBuffer) > maxPoints
                tBuffer = tBuffer(end-maxPoints+1:end);
                distData = distData(end-maxPoints+1:end);
                riskData = riskData(end-maxPoints+1:end);
            end
        else
            imgAnnotated = img;
            hText.String = 'Detected: - | Distance: - m | Risk: - | Conf: -';
            set(hWarn, 'Visible', 'off');
            set(hText, 'ForegroundColor', 'k');
        end

        % Update video feed
        imshow(imgAnnotated, 'Parent', hAx);
        title(hAx, sprintf('DASH CAM - Frame %d', frameIdx), 'FontSize', 14);

        % Update graphs only if we have data
        if ~isempty(distData) && ~isempty(tBuffer)
            % Clear axes and replot to avoid line accumulation
            cla(ax1);
            cla(ax2);
            
            % Plot distance data (now in meters)
            plot(ax1, tBuffer, distData, 'r-', 'LineWidth', 1.5);
            title(ax1, titles{1}, 'FontSize', 12, 'FontWeight', 'bold');
            xlabel(ax1, 'Frame Number');
            ylabel(ax1, 'Distance (m)');
            grid(ax1, 'on');
            
            % Plot risk data
            plot(ax2, tBuffer, riskData, 'b-', 'LineWidth', 1.5);
            title(ax2, titles{2}, 'FontSize', 12, 'FontWeight', 'bold');
            xlabel(ax2, 'Frame Number');
            ylabel(ax2, 'Risk (%)');
            grid(ax2, 'on');
            
            % Auto-adjust axes limits with proper error checking
            if length(tBuffer) >= 2
                xlim(ax1, [min(tBuffer), max(tBuffer)]);
                xlim(ax2, [min(tBuffer), max(tBuffer)]);
            end
            
            % Set y-limits with safe values (now in meters)
            if ~isempty(distData) && max(distData) > 0
                ylim(ax1, [0, min(5, max(distData)*1.1)]); % Cap at 5 meters
            else
                ylim(ax1, [0, 2]); % Default 2 meters
            end
            ylim(ax2, [0, 100]); % Risk always 0-100%
        end
        
        drawnow limitrate; % Use limitrate for better performance
    end

    %--------------------------------------------------------------
    % Cleanup function
    %--------------------------------------------------------------
    function closeGUI(~, ~)
        isRunning = false;
        if exist('cam', 'var')
            clear cam;
        end
        % Clear any playing sound
        clear sound;
        delete(hFig);
    end
end