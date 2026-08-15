%% Classify crack image and explain why 
clear; clc; close all

%% ===== Carregar dataset =====
imds = imageDatastore("C:\Users\felip\OneDrive\Eng. Civil\IC\Rodovia\Detector de trincas\Trincas_IA\Crack Images for Classification", ...
    "IncludeSubfolders", true, "LabelSource", "foldernames");

%% ===== Visualização =====
numExample = 16;
idx = randperm(numel(imds.Files), numExample);

I_tile = cell(numExample,1);
for i = 1:numExample
    I = readimage(imds, idx(i));
    I_tile{i} = insertText(I,[1,1],string(imds.Labels(idx(i))),'FontSize',20);
end

figure; imshow(imtile(I_tile));
title('Exemplos do dataset')

%% ===== Divisão =====
[imdsTrain, imdsValidation, imdsTest] = splitEachLabel(imds, 0.05, 0.05, 0.05);

%% ===== Rede pré-treinada =====
net = squeezenet;
inputSize = net.Layers(1).InputSize;

%% ===== Ajuste da rede =====
lgraph = layerGraph(net);
numClasses = numel(categories(imdsTrain.Labels));

lgraph = removeLayers(lgraph, {'ClassificationLayer_predictions'});

lgraph = replaceLayer(lgraph, 'prob', [
    fullyConnectedLayer(numClasses,'Name','fc_add')
    softmaxLayer('Name','softmax_layer')
    classificationLayer('Name','new_classoutput')
]);

%% ===== Data Augmentation =====
pixelRange = [-30 30];

imageAugmenter = imageDataAugmenter( ...
    'RandXReflection', true, ...
    'RandXTranslation', pixelRange, ...
    'RandYTranslation', pixelRange);

augimdsTrain = augmentedImageDatastore(inputSize(1:2), imdsTrain, ...
    'DataAugmentation', imageAugmenter);

augimdsValidation = augmentedImageDatastore(inputSize(1:2), imdsValidation);
augimdsTest = augmentedImageDatastore(inputSize(1:2), imdsTest);

%% ===== Treinamento =====
options = trainingOptions('adam', ...
    'MiniBatchSize',100, ...
    'MaxEpochs',5, ...
    'InitialLearnRate',2e-4, ...
    'Shuffle','every-epoch', ...
    'ValidationData',augimdsValidation, ...
    'ExecutionEnvironment',"auto", ...
    'ValidationFrequency',30, ...
    'Verbose',false, ...
    'Plots','training-progress');

netTransfer = trainNetwork(augimdsTrain, lgraph, options);

%% ===== Avaliação =====
[YPred, scores] = classify(netTransfer, augimdsTest);
YTest = imdsTest.Labels;

accuracy = mean(YPred == YTest);
disp("Acurácia: " + accuracy)

%% ===== Preparar Grad-CAM =====
lgraphGrad = layerGraph(netTransfer);
lgraphGrad = removeLayers(lgraphGrad, lgraphGrad.Layers(end).Name);
dlnet = dlnetwork(lgraphGrad);

softmaxName = 'softmax_layer';
featureLayerName = 'relu_conv10';

%% ===== Salvar tudo =====
classNames = categories(imdsTrain.Labels);

save('rede_trincas.mat', ...
    'netTransfer', ...
    'dlnet', ...
    'inputSize', ...
    'classNames', ...
    'softmaxName', ...
    'featureLayerName');

disp('Modelo salvo com sucesso!')
