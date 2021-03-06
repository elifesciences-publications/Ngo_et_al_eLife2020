%% Ngo et al., eLife 2020: Sleep spindles mediate hippocampal-neocortical coupling during long-duration ripples
%
% Calculate time-frequency representations for NC and HIPP time-locked to
% NREM- and REM-control events
%
% Requirements:
% - Fieldtrip added to Matlab search path
% - line 28: "additional_functions" folder added to search path
% - line 30: specification of root path containing "EEGs", "Ripples" and
%   "Control events" folder (see https://osf.io/3hpvr/)
%
% created by H.-V.V. Ngo

clear
close all


%% bookkeeping
%% check if fieldtrip is available
if contains(path,'fieldtrip')
    ft_defaults;
else
    error('FieldTrip not in path');
end


%% directories etc.
addpath('C:\Ngo_et_al_eLife2020\additional_functions')  %% specify path

dirRoot = 'C:\Ngo_et_al_eLife2020';                     %% specify path

svName  = 'tfr_nrem_remCtrl';                           %% filename for saved data


%% fundamental parameters
numType = 2;
numPat  = 14;
numCh   = 2;
numRep  = 100;

fsample = 1000;


%% results structure
out = [];

out.def.type    = {'NREM-ctrl'; 'REM-ctrl'};
out.def.label   = {'NC'; 'HIPP'};

out.dim.indiv   = 'Type x Trial x Channel x Freq x Time';
out.dim.grdavg  = 'Type x Channel x Freq x Time';

out.param.artfctPad = [-0.25 0.25];     %% padding applied to artifacts
out.param.stageoi   = [2 3 4 5];          %% sleep stages of interest, i.e. NREM.
out.param.minSlpLen = 3;                %% minimal required length of NREM to be analyzed
out.param.timePad   = [-3.1 2.1];      %% temporal padding for segmentation

out.time = -2.0 : 0.02 : 1.0;   numTime = numel(out.time);      %% time vector
out.freq = 1 : 0.5 : 20;        numFreq = numel(out.freq);      %% frequency vector

out.param.mwCycl                        = ceil(out.freq * 0.5);     %% number of cycles per frequency for morlet wavelets
out.param.mwCycl(out.param.mwCycl < 5)  = 5;
out.param.mwCycl(1:8)                   = [2 3 3 3 3 3 4 4];

out.dof     = nan(numPat,1);                        %% degrees of freedom, i.e. numbers of analyzed ripples per patient and channel
out.indiv   = [];                                   %% individual tfr per patient
out.grdavg  = nan(numType,numCh,numFreq,numTime);   %% grand average across patients


%% timekeeping
scrptSta = tic;


%% main loop across patients
for iPat = 1 : numPat
    fprintf('analyze patient %d', iPat);
    
    %% get useful parameters
    tmplt   = load(fullfile(dirRoot,'EEGs',sprintf('pat%02d_NC_supplement.mat',iPat)));
    datalen = tmplt.datalen;
    scoring = ismember(tmplt.scoring,out.param.stageoi);
    
    clear tmplt

    
    %% gather data and artifacts
    inEEG       = cell(numCh,1);
    artfctfltr  = zeros(numCh,datalen);

    for iCh = 1 : numCh
        %% load data
        inEEG{iCh}  = load(fullfile(dirRoot,'EEGs',sprintf('pat%02d_%s.mat',iPat,out.def.label{iCh})));                 %% EEG
        inSupplmt   = load(fullfile(dirRoot,'EEGs',sprintf('pat%02d_%s_supplement.mat',iPat,out.def.label{iCh})));      %% supplement
        

        %% prepare artifacts
        %.. add padding, ensure padding is within data range
        artfct                          = inSupplmt.artifacts + round(out.param.artfctPad * fsample);
        artfct(artfct(:,1) < 1,1)       = 1;
        artfct(artfct(:,2) > datalen,2) = datalen;
        
        %.. create binary artifact filter
        artfctfltr(iCh,:) = hvn_createBnrySignal(artfct,datalen);
        
        clear artfct

        %.. remove NREM and REM intervals shorter than minSlpLen
        cleanSlp                    = hvn_extrctBnryBouts(~artfctfltr);
        rmvIdx                      = diff(cleanSlp,1,2) < round(out.param.minSlpLen * fsample);
        rmvSamples                  = cell2mat(reshape(arrayfun(@(x,y)  x:y, cleanSlp(rmvIdx,1), cleanSlp(rmvIdx,2),'UniformOutput',0),1,sum(rmvIdx)));
        artfctfltr(iCh,rmvSamples)  = 1;
        
        clear inSupplmt artfct cleanSlp rmvIdx rmvSamples
    end

    
    %% append data and create binary vector indexing clean sleep data points
    godData         = ft_appenddata([],inEEG{:});
    godData.fsample = fsample;
    
    godfltr = all([scoring; ~artfctfltr]);

    clear inEEG scoring artfctfltr

    
    %% process ripples
    % extract ripple names to account for overall lower ripples numbers at
    % trial balancing
    inRipple = load(fullfile(dirRoot,'Ripples',sprintf('pat%02d_HIPP_ripples.mat',iPat)));      %% ripple events
    
    %.. segmentation
    tfg     = [];
    tfg.trl = [inRipple.EvtInfo.maxTime' + round(out.param.timePad(1) * fsample),...
               inRipple.EvtInfo.maxTime' + round(out.param.timePad(2) * fsample),...
               ones(inRipple.EvtInfo.numEvt,1) * round(out.param.timePad(1) * fsample)];
    
    tfg.trl(tfg.trl(:,1) < 1 | tfg.trl(:,2) > datalen | inRipple.rejects,:)     = [];     %% remove trials outside data range
    tfg.trl(arrayfun(@(x,y) ~all(godfltr(x:y)),tfg.trl(:,1),tfg.trl(:,2)),:)    = [];     %% remove trials overlapping with artifacts

    numRipple = size(tfg.trl,1);

    clear inRipple
    
    
    %% process control events
    ctrlNREM    = cell(1,numRep);
    ctrlREM     = cell(1,numRep);
    
    %.. loop across realizations
    for iRep = 1 : numRep
        %.. nrem
        inNREM    = load(fullfile(dirRoot,'Control events',num2str(iRep),sprintf('pat%02d_HIPP_controlNREM.mat',iPat)));        
            
        %.. trial definition
        tfg     = [];
        tfg.trl = [inNREM.nonEvtInfo.maxTime' + round(out.param.timePad(1) * fsample),...
                   inNREM.nonEvtInfo.maxTime' + round(out.param.timePad(2) * fsample),...
                   ones(inNREM.nonEvtInfo.numEvt,1) * round(out.param.timePad(1) * fsample)];

        tfg.trl(tfg.trl(:,1) < 1 | tfg.trl(:,2) > datalen,:)                        = [];   %% remove trials outside data range
        tfg.trl(arrayfun(@(x,y) ~all(godfltr(x:y)),tfg.trl(:,1),tfg.trl(:,2)),:)    = [];   %% remove trials overlapping with artifacts

        ctrlNREM{iRep} = tfg.trl;
        
        clear inNREM
        
        %.. rem
        inREM    = load(fullfile(dirRoot,'Control events',num2str(iRep),sprintf('pat%02d_HIPP_controlREM.mat',iPat)));
            
        %.. trial definition
        tfg     = [];
        tfg.trl = [inREM.nonEvtInfo.maxTime' + round(out.param.timePad(1) * fsample),...
                   inREM.nonEvtInfo.maxTime' + round(out.param.timePad(2) * fsample),...
                   ones(inREM.nonEvtInfo.numEvt,1) * round(out.param.timePad(1) * fsample)];

        tfg.trl(tfg.trl(:,1) < 1 | tfg.trl(:,2) > datalen,:)                        = [];   %% remove trials outside data range
        tfg.trl(arrayfun(@(x,y) ~all(godfltr(x:y)),tfg.trl(:,1),tfg.trl(:,2)),:)    = [];   %% remove trials overlapping with artifacts

        ctrlREM{iRep} = tfg.trl;
        
        clear REM            
    end     %% iRep
    
    
    %% balance trial numbers
    numNREM = cellfun(@(x) size(x,1),ctrlNREM);
    numREM  = cellfun(@(x) size(x,1),ctrlREM);

    minTrl          = min([numRipple numNREM numREM]);
    out.dof{iPat}   = minTrl;

    if minTrl > 0
        for iRep = 1 : numRep
            ctrlNREM{iRep}  = ctrlNREM{iRep}(randperm(numNREM(iRep),minTrl),:);
            ctrlREM{iRep}   = ctrlREM{iRep}(randperm(numREM(iRep),minTrl),:);
        end
    end
    
    
    %% calculate tfr
    for iRep = 1 : numRep
        %.. segmentation
        %.... nrem
        tfg     = [];
        tfg.trl = ctrlNREM{iRep};
        trlNREM = ft_redefinetrial(tfg,godData);
        
        tfg     = [];
        tfg.trl = ctrlREM{iRep};
        trlREM  = ft_redefinetrial(tfg,godData);
        
        %.. calculate tfr
        tfg             = [];
        tfg.output      = 'pow';
        tfg.method      = 'wavelet';
        tfg.keeptrials  = 'yes';
        tfg.toi         = out.time;
        tfg.foi         = out.freq;
        tfg.pad         = 'nextpow2';
        tfg.width       = out.param.mwCycl;
        tfg.polyremoval = 1;
        
        tmp_tfr         = ft_freqanalysis(tfg,trlNREM);
        ctrlNREM{iRep}  = squeeze(tmp_tfr.powspctrm);
        
        tmp_tfr         = ft_freqanalysis(tfg,trlREM);
        ctrlREM{iRep}   = squeeze(tmp_tfr.powspctrm);

        clear trlNREM trlREM tmp_tfr
            
    end     %% iRep
    
    
    %% average control repetitions and save data in output structure
    tmp_mat = nan(numType,minTrl,numCh,numFreq,numTime);

    tmp_nrem_mat    = nan(numRep,minTrl,numCh,numFreq,numTime);
    tmp_rem_mat     = nan(numRep,minTrl,numCh,numFreq,numTime);

    for iRep = 1 : numRep
        tmp_nrem_mat(iRep,:,:,:,:)  = ctrlNREM{iRep};
        tmp_rem_mat(iRep,:,:,:,:)   = ctrlREM{iRep};
    end
    
    tmp_mat(1,:,:,:,:) = squeeze(mean(tmp_nrem_mat,1));
    tmp_mat(2,:,:,:,:) = squeeze(mean(tmp_rem_mat,1));
    
    out.indiv = cat(2,out.indiv,tmp_mat);
    
    clear tmp_mat tmp_nrem_mat tmp_rem_mat
end     %% iSub


%% grand average across patients
out.grdavg = squeeze(mean(out.indiv,2));


%% statistical analysis: ripple vs. REM-control events
out.stats.time = -1 : 0.02 : 1;     numTimeStats = numel(out.stats.time);
out.stats.freq = out.freq;

out.stats.tval = zeros(numCh,numFreq,numTimeStats);
out.stats.pval = ones(numCh,numFreq,numTimeStats);
out.stats.mask = zeros(numCh,numFreq,numTimeStats,'logical');

for iCh = 1 : numCh
    numTrl = size(out.indiv,2);
    
    %.. statistic parameters
    sfg                     = [];
    sfg.parameter           = 'powspctrm';
    sfg.latency             = [out.stats.time(1) out.stats.time(end)];
    sfg.method              = 'montecarlo';
    sfg.statistic           = 'depsamplesT';
    sfg.correctm            = 'cluster';
    sfg.numrandomization    = 1000;
    sfg.neighbours          = [];
    sfg.clusteralpha        = 0.05;
    sfg.clusterstatistic    = 'maxsum';
    sfg.tail                = 0;
    sfg.alpha               = 0.025;

    sfg.design(1,1:2*numTrl) = [ones(1,numTrl) 2*ones(1,numTrl)];
    sfg.design(2,1:2*numTrl) = [1:numTrl 1:numTrl];

    sfg.ivar = 1;
    sfg.uvar = 2;

    %.. prepare data
    tmpData = cell(numTrl,2);

    for iTrl = 1 : numTrl
        tmpData{iTrl,1}.time                = out.time;
        tmpData{iTrl,1}.freq                = out.freq;
        tmpData{iTrl,1}.label               = {'dummy'};
        tmpData{iTrl,1}.dimord              = 'chan_freq_time';
        tmpData{iTrl,1}.powspctrm           = nan(1,numFreq,numTime);
        tmpData{iTrl,1}.powspctrm(1,:,:)    = squeeze(out.indiv(1,iTrl,iCh,:,:));

        tmpData{iTrl,2}                     = tmpData{iTrl,1};
        tmpData{iTrl,2}.powspctrm(1,:,:)    = squeeze(out.indiv(2,iTrl,iCh,:,:));
    end

    %.. perform statistic
    tmpStats = ft_freqstatistics(sfg,tmpData{1:numTrl,1},tmpData{1:numTrl,2});

    out.stats.pval(iCh,:,:) = tmpStats.prob;
    out.stats.tval(iCh,:,:) = tmpStats.stat;
    out.stats.mask(iCh,:,:) = tmpStats.mask;

    clear tmpStats tmpData
end


%% save results
save(fullfile(dirSave,[filSave '.mat']),'-struct','out');


%% timekeeping
fprintf('This analysis took %.2f s\n', toc(scrptSta));
