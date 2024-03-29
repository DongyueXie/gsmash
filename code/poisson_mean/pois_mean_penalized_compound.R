source("code/normal_mean_model_utils.R")
#'@title Solve poisson penalized problem via compound method
#'@description Formulate Poisson mean problem as likelihood + penalty
#'@param x data vector
#'@param w prior weights
#'@param prior_mean prior mean
#'@param sigma2k prior variance
#'@param optim_method optimization method in `optim` function
#'@param maxiter max number of iterations
#'@return a list of
#'  \item{posteriorMean:}{posterior mean}
#'  \item{posterior2nd_moment:}{posterior second moment}
#'  \item{obj_value:}{objective function values}
#'  \item{priorMean:}{prior mean}
#'  @example
#'  n = 10000
#'  mu = rnorm(n)
#'  x = rpois(n,exp(mu))
#'  pois_mean_penalized_compound(x)
#'@details The problem is
#'\deqn{x_i\sim Poisson(\exp(\mu_i)),}
#'\deqn{\mu_i\sim \sum_k w_k N(\beta,\sigma_k^2).}

library(nloptr)
pois_mean_penalized_compound = function(x,
                                         w = NULL,
                                         prior_mean = NULL,
                                         mixsd=NULL,
                                         maxiter = 100,
                                        verbose=FALSE,
                                        tol=1e-4){
  n = length(x)

  # init prior mean,
  if(is.null(prior_mean)){
    beta = log(sum(x)/n)
  }else{
    beta = prior_mean
  }

  if(is.null(mixsd)){
    ## how to choose grid in this case?
    mixsd = ebnm:::default_smn_scale(log(x+1),sqrt(1/(x+1)),mode=beta)
    #mixsd = c(1e-10,1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 0.16, 0.32, 0.64, 1, 2, 4, 8, 16)
    #mixsd = c(0,1e-3, 1e-2, 1e-1, 0.16, 0.32, 0.64, 1, 2, 4, 8, 16)
  }
  K = length(mixsd)

  if(is.null(w)){
    w = rep(1/K,K)
  }

  z_init = log(1+x)
  local_opts = list( "algorithm" = "NLOPT_LD_LBFGS","xtol_rel" = tol)
  out = nloptr(c(z_init,-z_init,w,beta),
               eval_f=h_obj,
               eval_grad_f=h_obj_grad,
               eval_g_eq=h_cstr,
               eval_jac_g_eq=h_cstr_grad,
               opts = list("algorithm"="NLOPT_LD_AUGLAG",
                           "local_opts" = local_opts,
                           "print_level"=verbose,
                           "maxeval" = maxiter,
                           "xtol_rel" = tol),
               y=x,grid=mixsd)

  z_hat = out$solution[1:n]
  s_hat = sqrt(exp(out$solution[(n+1):(2*n)]))
  w_hat = softmax(out$solution[(2*n+1):(2*n+K)])
  mu_hat = out$solution[(2*n+K+1)]
  m = S(z_hat,s_hat,w_hat,mu_hat,mixsd)

  return(list(posterior = list(posteriorMean_latent = m,
                               posteriorVar_latent = PV(z_hat,s_hat,w_hat,mu_hat,mixsd),
                               posteriorMean_mean = S_exp(z_hat,s_hat,w_hat,mu_hat,mixsd)),
              fitted_g = list(weight = w_hat,mean = mu_hat,sd = mixsd),
              fit =list(z=z_hat,s=s_hat,nloptr_fit = out)))

  # return(list(posteriorMean = m,
  #             w = w_hat,
  #             priorMean = mu_hat,
  #             nloptr_fit = out,
  #             z=z_hat,
  #             sigma2k=sigma2k))


}


#'objective function, sum over h_i()
#'@param params (z,s2,a,mu)
#'@param y data vector
#'@param grid prior sds
#'@return objective value, a scalar
h_obj = function(params,y,grid){
  n = length(y)
  K = length(grid)
  z = params[1:n]
  v = params[(n+1):(2*n)]
  s = sqrt(exp(v))
  w = softmax(params[(2*n+1):(2*n+K)])
  mu = params[2*n+K+1]
  return(h_obj_calc(z,s,w,mu,y,grid))
}

h_obj_calc = function(z,s,w,mu,y,grid){
  theta = S(z,s,w,mu,grid)
  return(sum(exp(theta)-y*theta-l_nm(z,s,w,mu,grid)-(theta-z)^2/2/s^2-log(s^2)/2))
}

#'@return the gradient of objective function
h_obj_grad = function(params,y,grid){
  n = length(y)
  K = length(grid)
  z = params[1:n]
  v = params[(n+1):(2*n)]
  s = sqrt(exp(v))
  a = params[(2*n+1):(2*n+K)]
  w = softmax(a)
  mu = params[2*n+K+1]
  return(h_obj_grad_calc(z,s,v,w,a,mu,y,grid))
}

h_obj_grad_calc = function(z,s,v,w,a,mu,y,grid){
  return(c(h_obj_d1_z_calc(z,s,w,mu,y,grid),h_obj_d1_s2_calc(z,s,w,mu,y,grid)*exp(v),h_obj_d1_g_calc(z,s,a,mu,y,grid)))
}

#'objective function derivative wrt z
#'@param params (z,s2,a,mu)
#'@param y data vector
#'@param grid prior sds
#'@return a length n vector of gradients
# h_obj_d1_z = function(params,y,grid){
#   n = length(y)
#   K = length(grid)
#   z = params[1:n]
#   s = sqrt(params[(n+1):(2*n)])
#   a = params[(2*n+1):(2*n+K)]
#   mu = params[2*n+K+1]
#   return(h_obj_d1_z_calc(z,s,a,mu,y,grid))
# }

h_obj_d1_z_calc = function(z,s,w,mu,y,grid){
  l_dz = l_nm_d1_z(z,s,w,mu,grid)
  l_dz2 = l_nm_d2_z(z,s,w,mu,grid)
  theta = S(z,s,w,mu,grid)
  return(-(y-exp(theta))*(1+s^2*l_dz2)-l_dz-(theta-z)*l_dz2)
}

#'objective function derivative wrt s2
#'@param theta (z,s2,a)
#'@param y data vector
#'@param grid prior sds
#'@return a length n vector of gradients
# h_obj_d1_s2 = function(params,y,grid){
#   n = length(y)
#   K = length(grid)
#   z = params[1:n]
#   s = sqrt(params[(n+1):(2*n)])
#   a = params[(2*n+1):(2*n+K)]
#   mu = params[2*n+K+1]
#   return(h_obj_d1_s2_calc(z,s,a,mu,y,grid))
#
# }

h_obj_d1_s2_calc = function(z,s,w,mu,y,grid){
  l_dz = l_nm_d1_z(z,s,w,mu,grid)
  l_dzds2 = l_nm_d2_zs2(z,s,w,mu,grid)
  l_ds2 = l_nm_d1_s2(z,s,w,mu,grid)
  theta = S(z,s,w,mu,grid)
  S_ds2 = l_dz + s^2*l_dzds2
  return(-(y-exp(theta))*S_ds2-l_ds2-(theta-z)*S_ds2/s^2+(theta-z)^2/2/s^4-1/2/s^2)
}

#'objective function derivative wrt a
#'@param theta (z,s2,a)
#'@param y data vector
#'@param grid prior sds
#'@return a length K vector of gradients
# h_obj_d1_g = function(params,y,grid){
#   n = length(y)
#   K = length(grid)
#   z = params[1:n]
#   s = sqrt(params[(n+1):(2*n)])
#   a = params[(2*n+1):(2*n+K)]
#   mu = params[2*n+K+1]
#   return(h_obj_d1_g_calc(z,s,a,mu,y,grid))
# }

h_obj_d1_g_calc = function(z,s,a,mu,y,grid){
  w = softmax(a)
  l_dzda = l_nm_d2_za(z,s,a,mu,grid)
  l_dzdmu = l_nm_d2_zmu(z,s,w,mu,grid)
  l_da = l_nm_d1_a(z,s,a,mu,grid)
  l_dmu = l_nm_d1_mu(z,s,w,mu,grid)
  theta = S(z,s,w,mu,grid)
  S_da = s^2*l_dzda
  S_dmu = s^2*l_dzdmu
  grad_a = -(y-exp(theta))*S_da - l_da - (theta-z)*S_da/s^2
  grad_mu = -(y-exp(theta))*S_dmu - l_dmu - (theta-z)*S_dmu/s^2
  return(c(c(colSums(grad_a)),c(sum(grad_mu))))
}





#'@title calculate constraint function
#'@param theta (z,s2,a)
#'@return a vector of length n, constraint function values
h_cstr = function(params,y,grid){
  n = length(y)
  K = length(grid)
  z = params[1:n]
  v = params[(n+1):(2*n)]
  s = sqrt(exp(v))
  a = params[(2*n+1):(2*n+K)]
  w = softmax(a)
  mu = params[2*n+K+1]
  return(h_cstr_calc(z,s,w,mu,grid))
}

h_cstr_calc = function(z,s,w,mu,grid){
  theta = S(z,s,w,mu,grid)
  return(log(s^2)+theta)
}

h_cstr_grad = function(params,y,grid){
  n = length(y)
  K = length(grid)
  z = params[1:n]
  v = params[(n+1):(2*n)]
  s = sqrt(exp(v))
  a = params[(2*n+1):(2*n+K)]
  w = softmax(a)
  mu = params[2*n+K+1]
  return(h_cstr_grad_calc(z,s,v,w,a,mu,grid))
}

h_cstr_grad_calc = function(z,s,v,w,a,mu,grid){
  return(cbind(diag(h_cstr_d1_z_calc(z,s,w,mu,grid)),diag(h_cstr_d1_s2_calc(z,s,w,mu,grid)*exp(v)),h_cstr_d1_g_calc(z,s,a,mu,grid)))
}

#'@title calculate constraint function derivative wrt z
#'@param theta (z,s2,a,mu)
#'@return a vector of length n gradient
# h_cstr_d1_z = function(params,y,grid){
#   n = length(y)
#   K = length(grid)
#   z = params[1:n]
#   s = sqrt(params[(n+1):(2*n)])
#   a = params[(2*n+1):(2*n+K)]
#   w = softmax(a)
#   mu = params[2*n+K+1]
#   return(h_cstr_d1_z_calc(z,s,w,mu,grid))
# }

h_cstr_d1_z_calc = function(z,s,w,mu,grid){
  return(1+s^2*l_nm_d2_z(z,s,w,mu,grid))
}

#'@title calculate constraint function derivative wrt s2
#'@param theta (z,s2,a,mu)
#'@return a vector of length n gradient
# h_cstr_d1_s2 = function(theta,y,grid){
#   n = length(y)
#   z = theta[1:n]
#   s2 = theta[(n+1):(2*n)]
#   a = theta[-(1:(2*n))]
#   return(h_cstr_d1_s2_calc(z,s2,a,grid))
# }

h_cstr_d1_s2_calc = function(z,s,w,mu,grid){
  return(1/s^2+l_nm_d1_z(z,s,w,mu,grid)+s^2*l_nm_d2_zs2(z,s,w,mu,grid))
}


#'@title The gradient of constraint function w.r.t a
#'@return a n*K matrix
# h_cstr_d1_a = function(theta,y,grid){
#   n = length(y)
#   K = length(grid)
#   z = theta[1:n]
#   s2 = theta[(n+1):(2*n)]
#   a = theta[-(1:(2*n))]
#   return(h_cstr_d1_a_calc(z,s2,a,grid))
# }

h_cstr_d1_g_calc = function(z,s,a,mu,grid){
  w = softmax(a)
  l_dzda = l_nm_d2_za(z,s,a,mu,grid)
  l_dzdmu = l_nm_d2_zmu(z,s,w,mu,grid)
  return(s^2*cbind(l_dzda,l_dzdmu))
}
