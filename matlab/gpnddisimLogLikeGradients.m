function g = gpnddisimLogLikeGradients(model,varargin)

% GPNDDISIMLOGLIKEGRADIENTS Compute the gradients of the log likelihood of a GPNDDISIM model.
% FORMAT
% DESC computes the gradients of the log likelihood of the given
% Gaussian process for use in a single input motif protein network.
% ARG model : the model for which the log likelihood is computed.
% RETURN g : the gradients of the parameters of the model.
% 
% SEEALSO : gpsimCreate, gpsimLogLikelihood, gpsimGradient
%
% COPYRIGHT : Neil D. Lawrence, 2006
%
% COPYRIGHT : Antti Honkela, 2007
%
% COPYRIGHT : Jaakko Peltonen, 2011
  
% GPSIM

if length(varargin)==2,
  update_kernel=varargin{1};
  update_mean=varargin{2};
else
  update_kernel=1;
  update_mean=1;
end;

covGrad = -model.invK + model.invK*model.m*model.m'*model.invK;
covGrad = 0.5*covGrad;


if (update_kernel==1),
  if isfield(model, 'proteinPrior') && ~isempty(model.proteinPrior)
    g = kernGradient(model.kern, model.timesCell, covGrad);
  else
    g = kernGradient(model.kern, model.t, covGrad);
  end
  
%  fprintf('gpdisimLogLikeGradients: g before any priors\n');
%   g'
%  pause
  
  % In case we need priors in.
  % Add contribution of any priors 
  if isfield(model, 'bprior'),
    g = g + kernPriorGradient(model.kern);
  end
else
  g = zeros(1,model.kern.nParams);
end;

  




if (update_mean==1),

  gmuFull = model.m'*model.invK;

  % if isfield(model, 'proteinPrior') && ~isempty(model.proteinPrior)
  %   if model.includeNoise
  %     ind = model.kern.comp{1}.diagBlockDim{1} + (1:model.kern.comp{1}.diagBlockDim{2});
  %     gmu = zeros(size(1, model.numGenes));
  
  %     for i = 1:model.numGenes
  %       gmu(i) = sum(gmuFull(ind));
  %       ind = ind + model.kern.comp{1}.diagBlockDim{i+1};
  %     end
  %   else
  %     ind = model.kern.diagBlockDim{1} + (1:model.kern.diagBlockDim{2});
  %     gmu = zeros(size(1, model.numGenes));
  
  %     for i = 1:model.numGenes
  %       gmu(i) = sum(gmuFull(ind));
  %       ind = ind + model.kern.diagBlockDim{i+1};
  %     end
  %   end
  
  % else
  
  if (model.numGenes>0) && (model.use_disimstartmean==1),
    %--------------------------------
    % Version with NDDISIM start mean
    %--------------------------------
    
    % Compute gradient for basal transcription rates
    gb=zeros(1, model.numGenes);
    for k=1:model.numGenes,
      % note that delay in the DISIM model does not affect the
      % contribution of the basal transcription, thus delays are
      % not applied to model.t here.
      delayedt=model.t;      
      indStart=length(model.t)*k + 1;
      indEnd=indStart+length(model.t)-1;
      gb(k)=gmuFull(indStart:indEnd)*((1-exp(-model.D(k)*delayedt))/model.D(k));
    end;
    % Add contribution of prior on B if it exists.
    if isfield(model, 'bprior');
      if model.numGenes>0,
	gb = gb + priorGradient(model.bprior, model.B);
      end;
    end
    % Multiply by factors from parameter transformations
    if model.numGenes>0,
      fhandle = str2func([model.bTransform 'Transform']);
      for k=1:length(gb),
	gb(k) = gb(k)*fhandle(model.B(k), 'gradfact', model.bTransformSettings{k});
      end;
    end;
    
    % Compute gradient for DISIM start mean
    gdisimstartmean=zeros(1, model.numGenes);
    for k=1:model.numGenes,
      % note that delay in the DISIM model does not affect the
      % decay of the starting RNA concentration, thus delays are
      % not applied to model.t here.
      indStart=length(model.t)*k + 1;
      indEnd=indStart+length(model.t)-1;
      gdisimstartmean(k)=gmuFull(indStart:indEnd)*exp(-model.D(k)*model.t);
    end;
    % Multiply by factors from parameter transformations
    if model.numGenes>0,
      fhandle = str2func([model.disimStartMeanTransform 'Transform']);
      for k=1:length(gdisimstartmean),
	gdisimstartmean(k) = gdisimstartmean(k)*fhandle(model.disimStartMean(k), 'gradfact', model.disimStartMeanTransformSettings{k});
      end;
    end;
    
    % Compute gradient for DISIM-level decays
    gd=zeros(1, model.numGenes);
    for k=1:model.numGenes,
      % note that delay in the DISIM model does not affect the
      % decay of the starting RNA concentration, or the
      % contribution of the basal transcription rate, thus delays are
      % not applied to model.t for those parts. However, delays do
      % affect the contribution of the POL2 mean ("simMean"), so
      % delays must be applied when computing the gradient with
      % respect to decay for that part of the mean function.
      delayedt=model.t-model.delay(k);      
      I=find(delayedt<0);
      delayedt(I)=0;
      
      indStart=length(model.t)*k + 1;
      indEnd=indStart+length(model.t)-1;
%      gd(k)=gmuFull(indStart:indEnd)*...
%	    ( (-(model.B(k)+model.S(k)*model.simMean)/(model.D(k)*model.D(k)))*(1-exp(-model.D(k)*model.t)) ...
%	      +(model.disimStartMean(k)-(model.B(k)+model.S(k)*model.simMean)/model.D(k))*exp(-model.D(k)*model.t).*(-model.t));    
      gd(k)=gmuFull(indStart:indEnd)*...
	    ( -model.B(k)/(model.D(k)*model.D(k))*(1-exp(-model.D(k)*model.t)) ...
              +model.B(k)/model.D(k)*exp(-model.D(k)*model.t).*model.t ...
	      +model.disimStartMean(k)*exp(-model.D(k)*model.t).*(-model.t) ...
              -model.simMean*model.S(k)/(model.D(k)*model.D(k))*(1-exp(-model.D(k)*delayedt)) ...
              +model.simMean*model.S(k)/model.D(k)*exp(-model.D(k)*delayedt).*delayedt ...
              );
    end;    
    % Apply factors from transformations, and add gradient of the
    % decays to the main decay-gradient from the kernel,
    if model.numGenes>0,
      decayIndices = model.disimdecayindices;
      decayTransformationSettings = model.disimdecaytransformationsettings;
      for k=1:length(decayIndices),
	g(decayIndices(k)) = g(decayIndices(k)) ...
	    + gd(k)*sigmoidabTransform(model.D(k), 'gradfact',decayTransformationSettings{k});  
      end;
    end;          

    % Compute gradient for SIM-level mean
    gsimmean=zeros(1, 1);
    indStart=1;
    indEnd=indStart+length(model.t)-1;
    gsimmean=gmuFull(indStart:indEnd)*(ones(indEnd-indStart+1,1));
    for k=1:model.numGenes,
      % note that delay in the DISIM model affects the contribution 
      % of the POL2 mean ("simMean"), so delays must be applied to time 
      % points when computing the gradient with respect to simMean.
      delayedt=model.t-model.delay(k);      
      I=find(delayedt<0);
      delayedt(I)=0;
      
      indStart=length(model.t)*k + 1;
      indEnd=indStart+length(model.t)-1;
      gsimmean=gsimmean+gmuFull(indStart:indEnd)*((1-exp(-model.D(k)*delayedt))*model.S(k)/model.D(k));
    end;
    % Multiply by factors from parameter transformations
    fhandle = str2func([model.simMeanTransform 'Transform']);
    gsimmean = gsimmean*fhandle(model.simMean, 'gradfact', model.simMeanTransformSettings);

    % Compute gradient for DISIM-level variance
    gdisimvar=zeros(1, model.numGenes);
    for k=1:model.numGenes,
      % note that delay in the DISIM model affects the contribution 
      % of the POL2 mean ("simMean"), so delays must be applied to time 
      % points when computing the gradient with respect to DISIM variance,
      % for the part of the mean function related to simMean.
      delayedt=model.t-model.delay(k);      
      I=find(delayedt<0);
      delayedt(I)=0;

      indStart=length(model.t)*k + 1;
      indEnd=indStart+length(model.t)-1;
      gdisimvar(k)=gmuFull(indStart:indEnd)*...
            ((1-exp(-model.D(k)*delayedt))*model.simMean/model.D(k)*0.5/model.S(k));
    end;    
    % Multiply by factors from parameter transformations, and add gradient of the
    % DISIM-variances to the main DISIM-variance gradient from the kernel
    if model.numGenes>0,
      disimvarIndices = model.disimvarianceindices;
      disimvarTransformationSettings = model.disimvariancetransformationsettings;
      for k=1:length(disimvarIndices),
        g(disimvarIndices(k)) = g(disimvarIndices(k)) ...
            + gdisimvar(k)*sigmoidabTransform(model.S(k)*model.S(k), 'gradfact',disimvarTransformationSettings{k});
      end;
    end;    

    % Compute gradient for DISIM-level delay
    gdisimdelay=zeros(1, model.numGenes);
    for k=1:model.numGenes,
      % note that delay in the DISIM model affects the contribution 
      % of the POL2 mean ("simMean"), so delays must be applied to time 
      % points when computing the gradient with respect to DISIM variance,
      % for the part of the mean function related to simMean.
      delayedt=model.t-model.delay(k);      
      I=find(delayedt<0);
      delayedt(I)=0;

      indStart=length(model.t)*k + 1;
      indEnd=indStart+length(model.t)-1;
      gdisimdelay(k)=gmuFull(indStart:indEnd)*...
            (-exp(-model.D(k)*delayedt).*(delayedt>0)*model.simMean*model.S(k));
    
%          +(model.simMean*model.S(k)/model.D(k))*(1-exp(-model.D(k)*tempt));
    
    end;    
    % gdisimdelay

    % Multiply by factors from parameter transformations, and add gradient of the
    % DISIM-variances to the main DISIM-variance gradient from the kernel
    if model.numGenes>0,
      disimdelayIndices = model.disimdelayindices;
      disimdelayTransformationSettings = model.disimdelaytransformationsettings;
      for k=1:length(disimdelayIndices),
        g(disimdelayIndices(k)) = g(disimdelayIndices(k)) ...
            + gdisimdelay(k)*sigmoidabTransform(model.delay(k), 'gradfact',disimdelayTransformationSettings{k});
      end;
    end;    
    
  else
    %--------------------------------
    % Version without DISIM start mean
    % TODO: this version of the code does not yet take into account delays in the model!
    %--------------------------------
    gdisimstartmean=[];
    
    numData = size(model.t, 1);
    ind = 1:numData;
    ind = ind + numData;
    %  gmu = zeros(size(1, model.numGenes));
    gmu = zeros(1, model.numGenes);
    for i = 1:model.numGenes
      gmu(i) = sum(gmuFull(ind));
      ind = ind + numData;
    end
    %end
    
    if model.numGenes>0,
      gb = gmu./model.D;
    end;
    
    % In case we need priors in.
    % Add prior on B if it exists.
    if isfield(model, 'bprior');
      if model.numGenes>0,
	gb = gb + priorGradient(model.bprior, model.B);
      end;
    end
  
    if model.numGenes>0,
      fhandle = str2func([model.bTransform 'Transform']);
      for k=1:length(gb),
	gb(k) = gb(k)*fhandle(model.B(k), 'gradfact', model.bTransformSettings{k});
      end;
    end;
  
    % Account for decay in mean.
    % This is a nasty hack to add the influence of the D in the mean to
    % the gradient already computed for the kernel. This is all very
    % clunky and sensitive to changes that take place elsewhere in the
    % code ...
    if model.numGenes>0,
      gd = -gmu.*(model.B+model.simMean)./(model.D.*model.D);
    end;

  
    % Apply transformations for decay-gradient in mean, and add to
    % main decay-gradient. Warning: only tested for 1 decay
    % parameter, the indices here might be slightly
    % incorrect in the general case!
    if model.numGenes>0,
      %decayIndices = [5];
      %for i = 3:model.kern.numBlocks
      %  decayIndices(end+1) = decayIndices(end) + 2;
      %end 
      decayIndices = model.disimdecayindices;
      decayTransformationSettings = model.disimdecaytransformationsettings;
      for k=1:length(decayIndices),
	g(decayIndices(k)) = g(decayIndices(k)) ...
	    + gd(k)*sigmoidabTransform(model.D(k), 'gradfact',decayTransformationSettings{k});  
      end;
    end;
  
    % Compute gradient for SIM-level mean
    gsimmean=zeros(1, 1);
    indStart=1;
    indEnd=indStart+length(model.t)-1;
    gsimmean=gmuFull(indStart:indEnd)*(ones(indEnd-indStart+1,1));
    for k=1:model.numGenes,
      indStart=length(model.t)*k + 1;
      indEnd=indStart+length(model.t)-1;
      gsimmean=gsimmean+gmuFull(indStart:indEnd)*(ones(indEnd-indStart+1,1)*model.S(k)/model.D(k));
    end;
    % Multiply by factors from parameter transformations
    fhandle = str2func([model.simMeanTransform 'Transform']);
    gsimmean = gsimmean*fhandle(model.simMean, 'gradfact', model.simMeanTransformSettings);

    % Compute gradient for DISIM-level variance
    gdisimvar=zeros(1, model.numGenes);
    for k=1:model.numGenes,
      indStart=length(model.t)*k + 1;
      indEnd=indStart+length(model.t)-1;
      gdisimvar(k)=gmuFull(indStart:indEnd)*...
            (ones(indEnd-indStart+1,1)*model.simMean/model.D(k)*0.5/model.S(k));
    end;    
    % Multiply by factors from parameter transformations, and add gradient of the
    % DISIM-variances to the main DISIM-variance gradient from the kernel
    if model.numGenes>0,
      disimvarIndices = model.disimvarianceindices;
      disimvarTransformationSettings = model.disimvariancetransformationsettings;
      for k=1:length(disimvarIndices),
        g(disimvarIndices(k)) = g(disimvarIndices(k)) ...
            + gdisimvar(k)*sigmoidabTransform(model.S(k)*model.S(k), 'gradfact',disimvarTransformationSettings{k});
      end;
    end;    
    
  end;  
  
else
  gb = zeros(1,model.numGenes);
  if (model.use_disimstartmean==1),
    gdisimstartmean = zeros(1,model.numGenes);
  else
    gdisimstartmean = [];
  end;  
  gsimmean = 0;
end;

%fprintf(1,'Gradient after modifications from mean terms:\n');
%g
%pause

if model.numGenes>0,
  g = [g gb gdisimstartmean gsimmean];
else
  g = [g gsimmean];  
end;

if isfield(model, 'fix')
  for i = 1:length(model.fix)
    g(model.fix(i).index) = 0;
  end
end
