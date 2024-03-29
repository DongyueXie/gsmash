#'@title a simulation study function
#'@importFrom parallel mclapply
#'@import Matrix


library(flashier)
library(Matrix)
library(parallel)
library(ebpmf)



sim_data_pmf_log = function(L,FF,sigma2,
                            var_type='by_col',
                            n_simu = 10,seed=12345){
  set.seed(seed)
  n = nrow(L)
  p = nrow(FF)
  Y = list()
  LF = tcrossprod(L,FF)
  if(var_type=='by_col'){
    Sigma2 = matrix(sigma2,n,p,byrow=T)
  }else if(var_type=='by_row'){
    Sigma2 = matrix(sigma2,n,p,byrow=F)
  }else{
    Sigma2 = sigma2
  }

  for(i in 1:n_simu){
    Lambda = exp(LF+matrix(rnorm(n*p,0,sqrt(Sigma2)),nrow=n,ncol=p))
    Y[[i]] = Matrix(matrix(rpois(n*p,Lambda),nrow=n,ncol=p),sparse = TRUE)
  }
  return(list(Y=Y,Factor=FF,Loading=L,sigma2=sigma2,n_simu=n_simu))
}

simu_study_PMF = function(simdata,n_cores = 1,
                          method_list=c('flash','ebpmf','nmf'),
                          ebnm_function = ebnm::ebnm_point_normal,
                          loadings_sign = 0,
                          factors_sign = 0,
                          Kmax=10,var_type='by_col',
                          init_tol=1e-5,
                          maxiter=100,tol=1e-5){
  n_simu = simdata$n_simu
  n_method = length(method_list)

  if(var_type=='by_row'){
    var.type = 1
  }else if(var_type=='by_col'){
    var.type = 2
  }else if(var_type=='constant'){
    var.type = 0
  }else{
    stop('Non-supported var type')
  }


  res = mclapply(1:n_simu,function(i){

    print(paste('Running simulation', i))

    fitted_model <- vector("list", n_method)
    names(fitted_model) <- method_list
    # check row and col sums
    rs = rowSums(simdata$Y[[i]])
    cs = colSums(simdata$Y[[i]])
    rm_row_idx = which(rs==0)
    rm_col_idx = which(cs==0)
    if(length(rm_row_idx)!=0){
      simdata$Y[[i]] = (simdata$Y[[i]])[-rm_row_idx,]
    }
    if(length(rm_col_idx)!=0){
      simdata$Y[[i]] = (simdata$Y[[i]])[,-rm_col_idx]
    }

    S = rowSums(simdata$Y[[i]])
    Y_normed = log(1+median(S)*simdata$Y[[i]]/S/0.5)
    Y_normed = Matrix(Y_normed,sparse = T)
    print('Fitting flash')

    fitted_model$flash = try(flash.init(Y_normed,var.type = var.type) %>%
          flash.set.verbose(0)%>%
          flash.add.greedy(Kmax = Kmax,ebnm.fn = ebnm_function,
                           init.fn =function(f) init.fn.default(f, dim.signs = c(loadings_sign, factors_sign))) %>%
          flash.backfit() %>%
          flash.nullcheck())

    # fitted_model$flash = try(flash(Y_normed,greedy.Kmax = Kmax,
    #                                var.type=var.type,verbose = 0,
    #                                backfit = TRUE,
    #                                ebnm.fn = ebnm_function))
    print('Fitting ebpmf PMF')
    fitted_model$ebpmf = try(ebpmf_log(simdata$Y[[i]],
                                       flash_control = list(Kmax=Kmax,ebnm.fn=ebnm_function,
                                                            loadings_sign=loadings_sign,
                                                            factors_sign=factors_sign),
                                       init_control=list(init_tol=init_tol),
                                       var_type=var_type,
                                       verbose = TRUE))
    # #mse_log = NULL
    # k_hat = NULL
    # if(class(fitted_model$flash)!='try-error'){
    #   #mse_log = c(mse_log,rmse(fitted_model$flash$fitted_values,tcrossprod(simdata$Loading[,,i],simdata$Factor[,,i])))
    #   k_hat = c(k_hat,fitted_model$flash$n.factors)
    # }else{
    #   #mse_log = c(mse_log,NA)
    #   k_hat = c(k_hat,NA)
    # }
    # if(class(fitted_model$ebpmf)!='try-error'){
    #   #mse_log = c(mse_log,rmse(fitted_model$ebpmf$fit_flash$fitted_values,tcrossprod(simdata$Loading[,,i],simdata$Factor[,,i])))
    #   k_hat = c(k_hat,fitted_model$ebpmf$fit_flash$n.factors)
    # }else{
    #   #mse_log = c(mse_log,NA)
    #   k_hat = c(k_hat,NA)
    # }
    # #names(mse_log) = c('flash','ebpmf')
    # names(k_hat) = c('flash','ebpmf')

    # return(list(fitted_model = fitted_model,
    #             #rmse_log=mse_log,
    #             k_hat=k_hat))
    return(list(fitted_model=fitted_model,rm_row_idx=rm_row_idx,rm_col_idx=rm_col_idx))

  },mc.cores = n_cores)
  return(list(sim_data=simdata,output = res))
}
