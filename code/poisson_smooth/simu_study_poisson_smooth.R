#'@title generate Poisson sequence data
#'@param n_simu number of simulation reps
#'@param n length of Poisson seq
#'@param snr signal  to noise ratio
#'@param count_size max of exp(b)
#'@param smooth_func cblocks, sblocks, heavi, angles, bursts, spike
#'@return a list of
#'  \item{X:}{data}
#'  \item{L:}{mean}
#'  \item{other imputs:}{sigma2,snr, ...}
#'@import wavethresh
#'@export
sim_data_smooth = function(n_simu,n=1024,snr=3,count_size,min_lambda = 0.01,smooth_func='sblocks',seed=12345){
  set.seed(seed)
  t = seq(0,1,length.out = n)
  if(smooth_func=='sblocks'){
    b = sblocks.f(t)
  }
  if(smooth_func=='cblocks'){
    b = cblocks.f(t)
  }
  if(smooth_func=='heavi'){
    b = heavi.f(t)
  }
  if(smooth_func=='angles'){
    b = angles.f(t)
  }
  if(smooth_func=='bursts'){
    b = bursts.f(t)
  }
  if(smooth_func=='spike'){
    b = spike.f(t)
  }

  #b = b - min(b)
  b = b/(max(b)/count_size)
  b[b<min_lambda] = min_lambda
  mu = log(b)
  sigma2 = var(mu[mu>0])/snr
  X = matrix(nrow=n_simu,ncol=n)
  L = matrix(nrow=n_simu,ncol=n)
  for(i in 1:n_simu){
    l = exp(mu+rnorm(n,0,sd=sqrt(sigma2)))
    L[i,] = l
    X[i,] = rpois(n,l)
  }
  return(list(X=X,latentX=log(L),b=mu,snr=snr,sigma2=sigma2,count_size=count_size,smooth_func=smooth_func,seed=seed,min_lambda=min_lambda))
}


mse = function (x, y) {
  mean((x - y)^2)
}
mae = function (x, y) {
  mean(abs(x - y))
}

#'@title compare methods for smoothing Poisson sequence
#'@import parallel
#'@import vebpm
#'@import smashr
#'
#'@export

simu_study_poisson_smooth = function(simdata,save_data=TRUE,
                                     method_list=c('vst',
                                                   'vst_hetero',
                                                   'lik_exp',
                                                   'lik_exp_top',
                                                   'split_smashpoi_dwt',
                                                   'split_vga_dwt',
                                                   'split_smashpoi_ndwt',
                                                   'split_vga_ndwt',
                                                   'smash_two_step',
                                                   'smash_two_step_hetero',
                                                   'smash'),
                                     smoother = 'smash',
                                     n_cores = 20,
                                     filter.number = 1,
                                     family='DaubExPhase',
                                     nug.est.limit = 0.3,
                                     maxiter=100){
  n_simu = nrow(simdata$X)
  n = ncol(simdata$X)
  n_method = length(method_list)
  res = mclapply(1:n_simu,function(i){
    fitted_model = vector('list',n_method)
    names(fitted_model) = method_list

    # if('vst_nug'%in%method_list){
    #   res_vst_nug = try(smash_gen_pois(simdata$X[i,],transformation='vst',smoother=smoother,
    #                                    filter.number = filter.number,family = family,est_nugget_maxiter = maxiter,est_nugget = TRUE))
    #   fitted_model$vst_nug = res_vst_nug
    # }
    #
    # if('vst_nug_top'%in%method_list){
    #   fitted_model$vst_nug_top = try(smash_gen_pois(simdata$X[i,],transformation='vst',smoother=smoother,
    #                                                 filter.number = filter.number,family = family,
    #                                                 est_nugget_maxiter = maxiter,est_nugget = TRUE,nug.est.limit=nug.est.limit))
    # }

    if('vst'%in%method_list){
      res_vst_smooth = try(smash_gen_pois(simdata$X[i,],transformation='vst',smoother=smoother,
                                          filter.number = filter.number,family = family,
                                          est_nugget = FALSE,
                                          homoskedastic = T))
      fitted_model$vst = res_vst_smooth
    }
    if('vst_hetero'%in%method_list){
      res_vst_smooth = try(smash_gen_pois(simdata$X[i,],transformation='vst',smoother=smoother,
                                          filter.number = filter.number,family = family,
                                          est_nugget = FALSE,
                                          homoskedastic = F))
      fitted_model$vst_hetero = res_vst_smooth
    }

    if('lik_exp'%in%method_list){
      res_lik_exp_logx_nug = try(smash_gen_pois(simdata$X[i,],transformation='lik_expan',smoother=smoother,
                                                filter.number = filter.number,family = family,
                                                ash_pm_init_for0 = TRUE,
                                                est_nugget_maxiter=2,lik_expan_at = 'logx',
                                                est_nugget = TRUE))
      fitted_model$lik_exp = res_lik_exp_logx_nug
    }
    if('lik_exp_top'%in%method_list){
      res_lik_exp_logx_nug_top = try(smash_gen_pois(simdata$X[i,],transformation='lik_expan',smoother=smoother,
                                                filter.number = filter.number,family = family,
                                                est_nugget_maxiter=2,lik_expan_at = 'logx',est_nugget = TRUE,
                                                ash_pm_init_for0 = TRUE,
                                                nug.est.limit = nug.est.limit))
      fitted_model$lik_exp_top = res_lik_exp_logx_nug_top
    }
    # if('lik_exp_logx_smooth'%in%method_list){
    #   res_lik_exp_logx_smooth = try(smash_gen_pois(simdata$X[i,],transformation='lik_expan',smoother=smoother,
    #                                                filter.number = filter.number,family = family,est_nugget_maxiter=maxiter,lik_expan_at = 'logx',est_nugget = FALSE))
    #   fitted_model$lik_exp_logx_smooth = res_lik_exp_logx_smooth
    # }
    # if('lik_exp_smashpoi_nug'%in%method_list){
    #   res_lik_exp_smashpoi_nug = try(smash_gen_pois(simdata$X[i,],transformation='lik_expan',smoother=smoother,
    #                                                 filter.number = filter.number,family = family,est_nugget_maxiter=maxiter,lik_expan_at = 'smash_poi',est_nugget = TRUE))
    #   fitted_model$lik_exp_smashpoi_nug = res_lik_exp_smashpoi_nug
    # }
    # if('lik_exp_smashpoi_nug_top'%in%method_list){
    #   fitted_model$lik_exp_smashpoi_nug_top = try(smash_gen_pois(simdata$X[i,],transformation='lik_expan',smoother=smoother,
    #                                                              filter.number = filter.number,
    #                                                              family = family,est_nugget_maxiter=maxiter,
    #                                                              lik_expan_at = 'smash_poi',est_nugget = TRUE,
    #                                                              nug.est.limit=nug.est.limit))
    # }
    # if('lik_exp_smashpoi_smooth'%in%method_list){
    #   res_lik_exp_smashpoi_smooth = try(smash_gen_pois(simdata$X[i,],transformation='lik_expan',smoother=smoother,
    #                                                    filter.number = filter.number,family = family,est_nugget_maxiter=maxiter,lik_expan_at = 'smash_poi',est_nugget = FALSE))
    #   fitted_model$lik_exp_smashpoi_smooth = res_lik_exp_smashpoi_smooth
    # }
    # if('lik_exp_iter_homo'%in%method_list){
    #   res_lik_exp_iter_homo = try(smash_gen_pois_iterative(simdata$X[i,],nugget_type = 'homoskedastic',
    #                                                        lik_expan_init ='logx',smoother = smoother,filter.number = filter.number,family = family,
    #                                                        maxiter=maxiter))
    #   fitted_model$lik_exp_iter_homo = res_lik_exp_iter_homo
    # }
    # if('lik_exp_iter_hetero'%in%method_list){
    #   res_lik_exp_iter_hetero = try(smash_gen_pois_iterative(simdata$X[i,],nugget_type = 'heteroskedastic',
    #                                                          lik_expan_init ='logx',smoother = smoother,filter.number = filter.number,family = family,
    #                                                          maxiter=maxiter))
    #   fitted_model$lik_exp_iter_hetero = res_lik_exp_iter_hetero
    # }

    # if('split_dwt_true'%in%method_list){
    #   fitted_model$split_dwt_true = try(pois_smooth_split(simdata$X[i,],wave_trans='dwt',m_init=simdata$latentX[i,],
    #                                                       filter.number = filter.number,family = family,maxiter=maxiter,
    #                                                       est_sigma2 = FALSE, sigma2_init = simdata$sigma2))
    # }
    #
    # if('split_runmed_dwt'%in%method_list){
    #   fitted_model$split_runmed_dwt = try(pois_smooth_split(simdata$X[i,],wave_trans='dwt',m_init='runmed',
    #                                                         filter.number = filter.number,family = family,maxiter=maxiter))
    # }
    # if('split_runmed_dwt_fix_nug'%in%method_list){
    #   fitted_model$split_runmed_dwt_fix_nug = try(pois_smooth_split(simdata$X[i,],wave_trans='dwt',m_init='runmed',
    #                                                                 filter.number = filter.number,family = family,maxiter=maxiter,
    #                                                                 est_sigma2 = FALSE, sigma2_init = simdata$sigma2))
    # }
    if('split_smashpoi_dwt'%in%method_list){
      fitted_model$split_smashpoi_dwt = try(ebps(simdata$X[i,],
                                                 init_control = list(m_init_method='smash_poi'),
                                                 smooth_control = list(wave_trans='dwt',
                                                                       filter.number = filter.number,
                                                                       family = family),
                                                 general_control = list(maxiter=maxiter)))
    }
    if('split_vga_dwt'%in%method_list){
      fitted_model$split_vga_dwt = try(ebps(simdata$X[i,],
                                                 init_control = list(m_init_method='vga'),
                                                 smooth_control = list(wave_trans='dwt',
                                                                       filter.number = filter.number,
                                                                       family = family),
                                                 general_control = list(maxiter=maxiter)))
    }
    if('split_smashpoi_ndwt'%in%method_list){
      fitted_model$split_smashpoi_ndwt = try(ebps(simdata$X[i,],
                                                 init_control = list(m_init_method='smash_poi'),
                                                 smooth_control = list(wave_trans='ndwt',
                                                                       ndwt_method = 'smash',
                                                                       filter.number = filter.number,
                                                                       family = family),
                                                 general_control = list(maxiter=maxiter)))
    }
    if('split_vga_ndwt'%in%method_list){
      fitted_model$split_vga_ndwt = try(ebps(simdata$X[i,],
                                            init_control = list(m_init_method='vga'),
                                            smooth_control = list(wave_trans='ndwt',
                                                                  ndwt_method = 'smash',
                                                                  filter.number = filter.number,
                                                                  family = family),
                                            general_control = list(maxiter=maxiter)))
    }
    # if('split_smashpoi_dwt_fix_nug'%in%method_list){
    #   fitted_model$split_smashpoi_dwt_fix_nug = try(pois_smooth_split(simdata$X[i,],wave_trans='dwt',m_init='smash_poi',
    #                                                                   filter.number = filter.number,family = family,maxiter=maxiter,
    #                                                                   est_sigma2 = FALSE, sigma2_init = simdata$sigma2))
    # }
    # if('split_logx_dwt'%in%method_list){
    #   fitted_model$split_logx_dwt = try(pois_smooth_split(simdata$X[i,],wave_trans='dwt',m_init='logx',
    #                                                       filter.number = filter.number,family = family,maxiter=maxiter))
    # }
    # if('split_logx_dwt_fix_nug'%in%method_list){
    #   fitted_model$split_logx_dwt_fix_nug = try(pois_smooth_split(simdata$X[i,],wave_trans='dwt',m_init='logx',
    #                                                               filter.number = filter.number,family = family,maxiter=maxiter,
    #                                                               est_sigma2 = FALSE, sigma2_init = simdata$sigma2))
    # }

    # if('split_runmed_ndwt'%in%method_list){
    #   fitted_model$split_runmed_ndwt = try(pois_smooth_split(simdata$X[i,],wave_trans='ndwt',m_init='runmed',
    #                                                          filter.number = filter.number,family = family,maxiter=maxiter))
    # }
    # if('split_runmed_ndwt_top'%in%method_list){
    #   fitted_model$split_runmed_ndwt_top = try(pois_smooth_split(simdata$X[i,],wave_trans='ndwt',m_init='runmed',
    #                                                              filter.number = filter.number,family = family,maxiter=maxiter,
    #                                                              sigma2_est_top = nug.est.limit))
    # }
    # if('split_runmed_ndwt_fix_nug'%in%method_list){
    #   fitted_model$split_runmed_ndwt_fix_nug = try(pois_smooth_split(simdata$X[i,],wave_trans='ndwt',m_init='runmed',
    #                                                                  filter.number = filter.number,family = family,maxiter=maxiter,
    #                                                                  est_sigma2 = FALSE, sigma2_init = simdata$sigma2))
    # }
    # if('split_logx_ndwt'%in%method_list){
    #   fitted_model$split_logx_ndwt = try(pois_smooth_split(simdata$X[i,],wave_trans='ndwt',m_init='logx',
    #                                                        filter.number = filter.number,family = family,maxiter=maxiter))
    # }
    # if('split_logx_ndwt_fix_nug'%in%method_list){
    #   fitted_model$split_logx_ndwt_fix_nug = try(pois_smooth_split(simdata$X[i,],wave_trans='ndwt',m_init='logx',
    #                                                                filter.number = filter.number,family = family,maxiter=maxiter,
    #                                                                est_sigma2 = FALSE, sigma2_init = simdata$sigma2))
    # }
    # if('split_ndwt_true'%in%method_list){
    #   fitted_model$split_ndwt_true = try(pois_smooth_split(simdata$X[i,],wave_trans='ndwt',m_init=simdata$latentX[i,],
    #                                                        filter.number = filter.number,family = family,maxiter=maxiter,
    #                                                        est_sigma2 = FALSE, sigma2_init = simdata$sigma2))
    # }

    # if('split_smashpoi_ndwt'%in%method_list){
    #   fitted_model$split_smashpoi_ndwt = try(pois_smooth_split(simdata$X[i,],wave_trans='ndwt',m_init='smash_poi',
    #                                                            filter.number = filter.number,family = family,maxiter=maxiter))
    # }
    # if('split_smashpoi_ndwt_fix_nug'%in%method_list){
    #   fitted_model$split_smashpoi_ndwt_fix_nug = try(pois_smooth_split(simdata$X[i,],wave_trans='ndwt',m_init='smash_poi',
    #                                                                    filter.number = filter.number,family = family,maxiter=maxiter,
    #                                                                    est_sigma2 = FALSE, sigma2_init = simdata$sigma2))
    # }
    if('smash'%in%method_list){
      t1 = Sys.time()
      res_smash = try(smash.poiss(simdata$X[i,]))
      res_smash = list(posterior=list(mean_smooth=res_smash,mean_log_smooth = log(res_smash)),run_time = difftime(Sys.time(),t1,unit='secs'))
      fitted_model$smash = res_smash
    }

    if('smash_two_step'%in%method_list){
      res_smash2 = try(smash_two_step(simdata$X[i,],homoskedastic=TRUE))
      fitted_model$smash_two_step = res_smash2
    }
    if('smash_two_step_hetero'%in%method_list){
      res_smash3 = try(smash_two_step(simdata$X[i,],homoskedastic=FALSE))
      fitted_model$smash_two_step_hetero = res_smash3
    }
    mse_smooth = simplify2array(lapply(fitted_model, function(x) {
      if(class(x)!='try-error'){
        mse(x$posterior$mean_smooth, exp(simdata$b))
      }else{
        NA
      }
    }))
    mae_smooth = simplify2array(lapply(fitted_model, function(x) {
      if(class(x)!='try-error'){
        mae(x$posterior$mean_smooth, exp(simdata$b))
      }else{
        NA
      }
    }))
    mse_latent_smooth = simplify2array(lapply(fitted_model, function(x) {
      if(class(x)!='try-error'){
        mse(x$posterior$mean_log_smooth,simdata$b)
      }else{
        NA
      }
    }))
    mae_latent_smooth = simplify2array(lapply(fitted_model, function(x) {
      if(class(x)!='try-error'){
        mae(x$posterior$mean_log_smooth,simdata$b)
      }else{
        NA
      }
    }))

    run_times = simplify2array(lapply(fitted_model,function(x){
      if(class(x)!='try-error'){
        x$run_time
      }else{
        NA
      }
    }))

    return(list(fitted_model=fitted_model,mse_smooth=mse_smooth,mae_smooth=mae_smooth,run_times=run_times,
                mse_latent_smooth=mse_latent_smooth,mae_latent_smooth=mae_latent_smooth))
  },mc.cores = n_cores
  )
  if(save_data){
    return(list(sim_data = simdata, output = res))
  }else{
    return(res)
  }
}





spike.f <- function (t)
  0.75 * exp(-500   * (t - 0.23)^2) +
  1.5  * exp(-2000  * (t - 0.33)^2) +
  3    * exp(-8000  * (t - 0.47)^2) +
  2.25 * exp(-16000 * (t - 0.69)^2) +
  0.5  * exp(-32000 * (t - 0.83)^2)


angles.f <- function (t) {
  s <- ((2 * t + 0.5) * (t <= 0.15)) +
    ((-12 * (t - 0.15) + 0.8) * (t > 0.15 & t <= 0.2)) +
    0.2 * (t > 0.2 & t <= 0.5) +
    ((6 * (t - 0.5) + 0.2) * (t > 0.5 & t <= 0.6)) +
    ((-10 * (t - 0.6) + 0.8) * (t > 0.6 & t <= 0.65)) +
    ((-0.5 * (t - 0.65) + 0.3) * (t > 0.65 & t <= 0.85)) +
    ((2 * (t - 0.85) + 0.2) * (t > 0.85))
  f <- 3/5 * ((5/(max(s) - min(s))) * s - 1.6) - 0.0419569
  return(f)
}


cblocks.f <- function (t) {
  pos <- c(0.1,0.13,0.15,0.23,0.25,0.4,0.44,0.65,0.76,0.78,0.81)
  hgt <- 2.88/5 * c(4,-5,3,-4,5,-4.2,2.1,4.3,-3.1,2.1,-4.2)
  f   <- rep(0,length(t))
  for (i in 1:length(pos))
    f <- f + (1 + sign(t - pos[i])) * (hgt[i]/2)
  f[f < 0] <- 0
  return(f)
}

sblocks.f <- function (t) {

  n = length(t)
  return(c(rep(0,n/8),rep(0.5,n/4),rep(0,n/8),rep(1.5,n/8),rep(0,n/8),rep(3,n/8),rep(0,n/8)))
}


# This defines the "Heavisine" signal.
heavi.f <- function (t) {
  heavi <- 4 * sin(4 * pi * t) - sign(t - 0.3) - sign(0.72 - t)
  f <- heavi/sqrt(var(heavi)) * 1 * 2.99/3.366185
  f <- f - min(f)
  return(f)
}

# This defines the "Bursts" signal.
bursts.f <- function (t) {
  I1 <- exp(-(abs(t - 0.2)/0.01)^1.2) * (t <= 0.2) +
    exp(-(abs(t - 0.2)/0.03)^1.2) * (t > 0.2)
  I2 <- exp(-(abs(t - 0.3)/0.01)^1.2) * (t <= 0.3) +
    exp(-(abs(t - 0.3)/0.03)^1.2) * (t > 0.3)
  I3 <- exp(-(abs(t - 0.4)/0.01)^1.2) * (t <= 0.4) +
    exp(-(abs(t - 0.4)/0.03)^1.2) * (t > 0.4)
  f  <- 2.99/4.51804 * (4*I1 + 3*I2 + 4.5*I3)
  return(f)
}


