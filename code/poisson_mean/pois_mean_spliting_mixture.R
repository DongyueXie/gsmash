

source("code/poisson_mean/pois_mean_GMGM.R")
pois_mean_split_mixture = function(x,s=NULL,
                                   mixsd = NULL,
                                   w=NULL,
                                   tol=1e-5,maxiter=1e3,
                                   ebnm_params=NULL,
                                   optim_method ='L-BFGS-B'){
  n = length(x)


  if(is.null(ebnm_params)){
    ebnm_params = ebnm_params_default()
  }else{
    temp = ebnm_params_default()
    for(i in 1:length(ebnm_params)){
      temp[[names(ebnm_params)[i]]] = ebnm_params[[i]]
    }
    ebnm_params = temp
  }
  if(is.null(s)){
    s = 1
  }
  if(length(s)==1){
    s = rep(s,n)
  }

  if(is.null(mixsd)){

    ## how to choose grid in this case?
    #mixsd = c(1e-10,1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 0.16, 0.32, 0.64, 1, 2, 4, 8, 16)
    sigma2k = (ebnm:::default_smn_scale(log(x/s+1),sqrt(1/(x/s+1)),mode=log(sum(x)/sum(s)))[-1])^2
    if(min(sigma2k)>1e-4){
      sigma2k =c(1e-4,sigma2k)
    }
    #mixsd = c(1e-3, 1e-2, 1e-1, 0.16, 0.32, 0.64, 1, 2, 4, 8, 16)
  }else{
    sigma2k = mixsd^2
  }
  K = length(sigma2k)

  if(is.null(w)){
    w = rep(1/K,K)
  }

  b_pm = rep(0,n)
  b_pv = rep(1/n,n)
  M = matrix(0,nrow=n,ncol=K)
  V = matrix(1/n,nrow=n,ncol=K)
  Sigma2k = matrix(sigma2k,nrow=n,ncol=K,byrow=T)
  X = matrix(x,nrow=n,ncol=K,byrow=F)
  lW = matrix(log(w),nrow=n,ncol=K,byrow=T)
  qz = matrix(0,nrow=n,ncol=K)
  obj = rep(0,maxiter+1)
  obj[1] = -Inf

  for (iter in 1:maxiter) {

    # # # VGA
    # for(i in 1:n){
    #   for (k in 1:K) {
    #     temp = pois_mean_GG1(x[i],s[i],b_pm[i],sigma2k[k],optim_method,M[i,k],V[i,k])
    #     M[i,k] = temp$m
    #     V[i,k] = temp$v
    #   }
    # }

    # for each K, solve a vectorized version
    for(k in 1:K){
      opt = optim(c(M[,k],log(V[,k])),
                  fn = pois_mean_GG_opt_obj,
                  gr = pois_mean_GG_opt_obj_gradient,
                  x=x,
                  s=s,
                  beta=b_pm,
                  sigma2=sigma2k[k],
                  n=n,
                  method = optim_method)
      M[,k] = opt$par[1:n]
      V[,k] = exp(opt$par[(n+1):(2*n)])
    }

    qz = X*M-s*exp(M+V/2)+lW-log(Sigma2k)/2-(M^2+V-2*M*b_pm+matrix(b_pm^2+b_pv,nrow=n,ncol=K,byrow=F))/Sigma2k/2 + log(V)/2
    #browser()
    qz = qz - apply(qz,1,max)
    qz = exp(qz)
    qz = qz/rowSums(qz)
    qz = pmax(qz,1e-15)

    pseudo_s = sqrt(1/c(rowSums(qz/Sigma2k)))
    pseudo_x = c(rowSums(qz*M/Sigma2k))*pseudo_s^2
    # EBNM
    res = ebnm(pseudo_x,pseudo_s,
               mode=ebnm_params$mode,
               prior_family=ebnm_params$prior_family,
               scale = ebnm_params$scale,
               g_init = ebnm_params$g_init,
               fix_g = ebnm_params$fix_g,
               output = ebnm_params$output,
               optmethod = ebnm_params$optmethod)
    b_pm = res$posterior$mean
    b_pv = res$posterior$sd^2
    H = res$log_likelihood + sum(log(2*pi*pseudo_s^2)/2)+sum((pseudo_x^2-2*pseudo_x*b_pm+b_pm^2+b_pv)/pseudo_s^2/2)

    # Update w
    w = colMeans(qz)
    w = pmax(w, 1e-8)

    # ELBO
    lW = matrix(log(w),nrow=n,ncol=K,byrow=T)
    obj[iter+1] = sum(qz*(X*M-s*exp(M+V/2)+lW-log(Sigma2k)/2-(M^2+V-2*M*b_pm+matrix(b_pm^2+b_pv,nrow=n,ncol=K,byrow=F))/2/Sigma2k-log(qz)+log(V)/2)) + H
    if((obj[iter+1]-obj[iter])<tol){
      obj = obj[1:(iter+1)]
      break
    }

  }

  return(list(posterior = list(posteriorMean_latent_mu = rowSums(qz*M),
                               posteriorMean_latent_b = b_pm,
                               posterior2nd_moment_latent_mu = rowSums(qz*(M^2+V)),
                               posteriorVar_latent_b = b_pv,
                               posteriorMean_mean = rowSums(qz*exp(M + V/2))),
              fitted_g = list(g_mu = list(weight=w,var=sigma2k),g_b = res$fitted_g),
              obj_value=obj,
              fit = list(ebnm_fit=res,M=M,V=V,qz=qz)))

  #return(list(posteriorMean_mu=rowSums(qz*M),posterior2nd_moment= rowSums(qz*(M^2+V)),M=M,V=V,obj_value=obj,w=w,qz=qz,posteriorMean_b=b_pm,ebnm_res = res))

}


ebnm_params_default = function(){
  return(list(prior_family='point_laplace',
              mode='estimate',
              scale = "estimate",
              g_init = NULL,
              fix_g = FALSE,
              output = output_default(),
              optmethod = NULL))
}
