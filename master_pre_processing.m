% This script performs several pre_processing steps on EEG recordings. The
% code makes heavy use of EEGLAB 2019.1 and all credits go to the
% developpers of the EEGLAB toolbox.



%% Terms and conditions
%  ====================

% Available under the terms of the Berkeley Software Distribution licence:
% Copyright (c) 2020, Laboratory for Brain-Machine Interfaces and
% Neuromodulation, Pontificia Universidad Católica de Chile, hereafter
% referred to as the "Organization".
% All rights reserved.
%
% Redistribution and use in source and binary forms are permitted
% provided that the above copyright notice and this paragraph are
% duplicated in all such forms and that any documentation,
% advertising materials, and other materials related to such
% distribution and use acknowledge that the software was developed
% by the Organization. The name of the
% Organization may not be used to endorse or promote products derived
% from this software without specific prior written permission.
% THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
% IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
% WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.



%% Important user-defined variables
%  ================================

% THESE STEPS CAN BE CHANGED IN ORDER WITHOUT ANY FURTHER CHANGES
% NEEDED IN THE SCRIPT
allSteps = {...
    'eeglabfilter', ...
    'extractsws', ...
    'noisyperiodreject', ...
    'noisychans2zeros', ...
    'rejectchans', ...
    'chan_interpol', ...
    'rereference', ...
    'separate_trial_grps'};
% FOR CLEANED DATA:
% extractSWS, customfilter,
% noisychans2zeros, noisyperiodreject, rejectchans, rereference,
% performica, reject_IC, chan_interpol, separate_trial_grps
% FOR DETRENDED DATA:
% extractsws, noisychans2zeros, noisyperiodreject, chan_interpol,
% separate_trial_grps, defdetrend, rereference
% FOR WHOLE RECORDING DATA:
% eeglabfilter, noisychans2zeros, noisyperiodreject, rejectchans,
% chan_interpol, rereference

% Define all steps to be performed: 0 for false and 1 for true
% extractsws              Extract SWS periods of datasets
% defdetrend              Detrend the dataset (quadtratic, linear,
%                         continuous, discontinuous)
% eeglabfilter            Filtfilt processing. Parameters set when
%                         when function called in script
% customfilter            Build and apply a custom zero-phase Fir
%                         FiltFilt bandpass filter
% medianfilter            Median filtering of noise artefacts of
%                         low-frequency occurence
% basecorrect             Baseline correction of signal according to
%                         time vector given by 'baselineCorr'.
% noisychans2zeros        Interpolation of noisy channels based on
%                         manually generated table with noisy chan info
% noisyperiodreject       Rejection of noisy channels based on manually
%                         generated table with noisy period info
% rejectchans             Reject non-wanted channels
% rereference             Re-reference channels to choosen reference.
%                         Reference is choosen when function is called
%                         in script
% performica              Run ICA on datasets. This step takes a while
% reject_IC               Extract information about artifact components
%                         and reject these
% chan_interpol           Interpolate rejected channels (all 0)
% downsample              Downsample datsets to user-defined sample fr
% separate_trial_grps     Separate trial series into groups. Parameters
%                         set when function is called in script.

data_appendix            = 'separate_trial_grps';
% Define folder name and dataset appendix for datasets

pathData            = 'D:\germanStudyData\datasetsSETS\Ori_CueNight';
% String of file path to the mother stem folder containing the datasets

dataType            = '.mff'; % {'.cdt', '.set', '.mff'}
% String of file extension of data to process

stimulation_seq     = 'switchedOFF_switchedON';
% {'switchedON_switchedOFF', 'switchedOFF_switchedON'}
% recordings --> trigger1 on, trigger1 off, trigger2 on, trigger2 off, ...
% "on_off" = [ongoing stimulation type 1, post-stimulation type 1] and
% "off_on" = [pre-stimulation type 1, ongoing stimulation type 1], where
% "pre-stimulation type 1" is actually post-stimulation type 2!
% On and Off therefore refers to the current state of the stimulation
% ("switched on" or "switched off").

baselineCorr = []; % [-7000 0] Array of min and max (ms) for baseline
% Baseline correction when epochs are extracted from dataset in
% f_sep_trial_groups. Leave empty if no correction is desired.


trials2rejFile   = '';
% Path to .mat file that contains information about trials to reject
% (explanations about organization of the file in f_sep_trial_groups

trials2rejVar    = 'comps2reject';
% Name of variable that holds the information about the trials to reject
% inside the .mat file

% Modifiable declarations inside several files are also possible and tagged
%   |===USER INPUT===|
%
%   ...
%
%   |=END USER INPUT=|

%                         +-------------------+
% ------------------------| END OF USER INPUT |----------------------------
%                         +-------------------+



%% Setting up user land
%  ====================
% -------------------------------------------------------------------------
% Define variables to be shared across workspaces
global str_base

% -------------------------------------------------------------------------
% Here we set up the list of recording files that will be processed in the
% script
ls_files        = dir(pathData);

% "dir" is also listing the command to browse current folder (".") and step
% out of folder (".."), so we reject these here
rej_dot         = find(strcmp({ls_files.name}, '.'));
rej_doubledot   = find(strcmp({ls_files.name}, '..'));
rej             = [rej_dot rej_doubledot];

ls_files(rej)   = [];

% Reject files that do not correspond to the user-defined format
rej_nonformat   = find(~contains({ls_files.name}, dataType));

ls_files(rej_nonformat) = [];

num_files       = size(ls_files, 1);

% -------------------------------------------------------------------------
% Stop here when no files have been found
if isempty(ls_files) || num_files == 0
    error('No datasets to process. Verify variables "pathData" and "dataType".')
end

% -------------------------------------------------------------------------
% Here, we locate EEGLAB toolbox since the path might differ between
% systems. This will then add the functions the script needs to MATLAB path
locateEeglab = which('eeglab.m');
[folderEEGLAB, ~, ~] = fileparts(locateEeglab);
addpath(genpath(folderEEGLAB))

% -------------------------------------------------------------------------
% Correcting potential error sources and clearing unnecessary variables
if strcmp(pathData(end), filesep)
    pathData(end)       = [];
end

clearvars rej rej_dot rej_doubledot rej_nonformat globalvars


% -------------------------------------------------------------------------
% Create folder structures for saving the datasets after processing
if contains(pathData, 'preProcessing')
    savePath = erase(pathData, extractAfter(pathData, 'preProcessing'));
else
    savePath = strcat(pathData, filesep, 'preProcessing');
end

% Adapt savePath to defined appendix
savePath = strcat(savePath, filesep, data_appendix);

if ~exist(savePath, 'dir')
    mkdir(savePath);
end

% End of user land setup
% ======================



%% The core of the script
%  ======================
% Every script seems rough on the outside, but has a soft core, so treat it nicely.

tic;
for s_file = 1 : num_files
    
    fprintf('\n<!> Running %s (%d/%d)...\n', ...
        ls_files(s_file).name, s_file, num_files) % Report stage
    
    %% 0. Define subject
    %  =================
    % ---------------------------------------------------------------------
    % Here, we extract the string of the subject number and the recording
    % session
    % |===USER INPUT===|
    str_subj            = extractAfter(ls_files(s_file).name, 'RC_');
    str_subj            = extractBefore(str_subj, '_');
    
    str_session         = str_subj(3); % Number of session
    str_subjnum     	= str_subj(1:2); % Number of subject
    % |=END USER INPUT=|
    
    if strcmp(dataType, '.set')
        % Extract the last step performed on the datset
        str_savefile    = extractBefore(ls_files(s_file).name, dataType);
        str_parts       = strsplit(str_savefile, '_');
        str_savefile    = extractBefore(str_savefile, ...
            strcat('_', str_parts(end)));
    else
        % Else, just get the file name without extension since no step
        % performed yet
        str_savefile    = extractBefore(ls_files(s_file).name, dataType);
        % The str_savefile will be adapted according to
        % the last step performed later.
    end
    
    str_base = str_savefile;
    
    % Appendix to dataset name accordingly to defined string:
    % This will allow to collect databases easier just by running "dir"
    % on pathData.
    str_savefile = strcat(str_savefile, '_', data_appendix, ...
        '_', stimulation_seq, '.set');
    
    % ---------------------------------------------------------------------
    % This is useful in order to store the history of EEGLAB functions
    % called during file processing
    lst_changes         = {};
    
    % ---------------------------------------------------------------------
    % Break out of loop if the subject dataset has already been processed
    if exist(strcat(savePath, filesep, str_savefile), 'file')
        fprintf('... skipped because already exists\n\n')
        continue
    end
    % End of subject definition
    % =========================
    
    
    
    %% 1. Import datasets into EEGLAB-like structures
    %  ==============================================
    
    [EEG, lst_changes{end+1,1}] = f_load_data(...
        ls_files(s_file).name, pathData, dataType);
    % End of import
    % =============
    
    
    
    %% 2. Perform pre-processing steps
    %  ===============================
    
    for i_step = 1:numel(allSteps)
        
        thisStep    = char(allSteps(i_step));
        stepsInRun  = 0;
        
        
        if strcmp(thisStep, 'extractsws')
            run p_extract_sws.m
            stepsInRun = stepsInRun + 1;
        end
        
        
        if strcmp(thisStep, 'eeglabfilter')
            run p_eeglabfilter.m
            stepsInRun = stepsInRun + 1;
        end
        
        
        if strcmp(thisStep, 'customfilter')
            run p_standalone/p_design_filter.m
            stepsInRun = stepsInRun + 1;
        end
        
        
        if strcmp(thisStep, 'medianfilter')
            %         run p_medfilt.m
            stepsInRun = stepsInRun + 1;
            warning('MedFilt was set to be run but was skipped since commented!')
        end
        
        
        if strcmp(thisStep, 'noisychans2zeros')
            run p_set_zerochans.m
            stepsInRun = stepsInRun + 1;
        end
        
        
        if strcmp(thisStep, 'noisyperiodreject')
            run p_noise_periods.m
            stepsInRun = stepsInRun + 1;
        end
        
        
        if strcmp(thisStep, 'rejectchans')
            run p_chan_reject.m
            stepsInRun = stepsInRun + 1;
        end
        
        
        if strcmp(thisStep, 'performica')
            [EEG, lst_changes{end+1,1}] = f_ica(EEG);
            stepsInRun = stepsInRun + 1;
        end
        
        
        if strcmp(thisStep, 'reject_IC')
            [EEG, lst_changes{end+1,1}] = f_reject_ICs(...
                EEG, trials2rejFile, trials2rejVar);
            stepsInRun = stepsInRun + 1;
        end
        
        
        if strcmp(thisStep, 'chan_interpol')
            run p_interpolate.m
            stepsInRun = stepsInRun + 1;
        end
        
        
        if strcmp(thisStep, 'basecorrect')
            [EEG, lst_changes{end+1,1}] = pop_rmbase(EEG, baselineCorr);
            stepsInRun = stepsInRun + 1;
        end
        
        
        if strcmp(thisStep, 'separate_trial_grps')
            % Add the history of all called functions to EEG structure
            if ~isfield(EEG, 'lst_changes')
                EEG.lst_changes = lst_changes;
            else
                EEG.lst_changes(...
                    numel(EEG.lst_changes) + 1 : ...
                    numel(EEG.lst_changes) + numel(lst_changes)) = ...
                    lst_changes;
            end
            [EEG_Odor, EEG_Sham, set_sequence] = ...
                f_sep_trial_groups(EEG, stimulation_seq, ...
                trials2rejFile, trials2rejVar);
            stepsInRun = stepsInRun + 1;
        end
        
        
        if strcmp(thisStep, 'defdetrend')
            [EEG_Odor.data, lst_changes{end+1,1}] = ...
                f_detrend(EEG_Odor.data, 1, true, {});
            [EEG_Sham.data, lst_changes{end+1,1}] = ...
                f_detrend(EEG_Sham.data, 1, true, {});
            stepsInRun = stepsInRun + 1;
        end
        
        
        if strcmp(thisStep, 'rereference')
            [EEG, lst_changes{end+1,1}] = f_offlinereference(EEG);
            stepsInRun = stepsInRun + 1;
        end
        
        
        % End loop check
        if stepsInRun == 0
            error('Current step string not matching with any option in code')
        elseif stepsInRun > 1
            error('More than one step performed during one loop')
        else
            fprintf('\n<!> Done with %s\n\n', thisStep)
        end
        
    end
    % End of pre-processing
    % =====================
    
    
    
    %% 3. Save dataset
    %  ===============
    
    if any(strcmp(allSteps, 'separate_trial_grps'))
        str_savefile_sham  = strcat(extractBefore(str_savefile, '.set'), ...
            '_Sham', extractAfter(str_savefile, stimulation_seq));
        str_savefile_odor  = strcat(extractBefore(str_savefile, '.set'), ...
            '_Odor', extractAfter(str_savefile, stimulation_seq));
        
        [EEG_Odor] = pop_saveset( EEG_Odor, ...
            'filename', str_savefile_odor, ...
            'filepath', savePath);
        [EEG_Sham] = pop_saveset( EEG_Sham, ...
            'filename', str_savefile_sham, ...
            'filepath', savePath);
    else
        % Add the history of all called functions to EEG structure
        if ~isfield(EEG, 'lst_changes')
            EEG.lst_changes = lst_changes;
        else
            EEG.lst_changes(...
                numel(EEG.lst_changes) + 1 : ...
                numel(EEG.lst_changes) + numel(lst_changes)) = ...
                lst_changes;
        end
        [EEG] = pop_saveset( EEG, ...
            'filename', str_savefile, ...
            'filepath', savePath);
    end
    
    clearvars EEG_Odor EEG_Sham EEG
end

toc
