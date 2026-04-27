 function prepareKaggleDataset
 

kaggleRoot = fullfile(pwd,'vehicle-pedestrian');  % folder of images
annotationCSV = fullfile(kaggleRoot,'annotations.csv');
outFolder = fullfile(pwd,'dataset');

if ~exist(outFolder,'dir')
    mkdir(outFolder);
end

% Read annotations
T = readtable(annotationCSV);
disp('Annotations loaded successfully.');

% Check column names
cols = T.Properties.VariableNames;
disp(cols);

% Assuming columns: filename, xmin, ymin, xmax, ymax, class
for i = 1:height(T)
    imgName = string(T.filename(i));
    className = string(T.class(i));
    bbox = [T.xmin(i), T.ymin(i), T.xmax(i), T.ymax(i)];

    imgPath = fullfile(kaggleRoot,'images',imgName);
    if ~isfile(imgPath)
        continue;
    end
    I = imread(imgPath);

    % Crop and resize
    xmin = max(1,bbox(1)); ymin = max(1,bbox(2));
    xmax = min(size(I,2),bbox(3)); ymax = min(size(I,1),bbox(4));
    crop = imcrop(I,[xmin ymin xmax-xmin ymax-ymin]);
    crop = imresize(crop,[224 224]);

    % Save under class folder
    classFolder = fullfile(outFolder,className);
    if ~exist(classFolder,'dir')
        mkdir(classFolder);
    end
    imwrite(crop,fullfile(classFolder,sprintf('%s_%05d.jpg',className,i)));
end

disp('Dataset prepared successfully in "dataset" folder.');
end
