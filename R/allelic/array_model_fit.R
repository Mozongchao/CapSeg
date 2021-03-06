## The Broad Institute
## SOFTWARE COPYRIGHT NOTICE AGREEMENT
## This software and its documentation are copyright (2012) by the
## Broad Institute/Massachusetts Institute of Technology. All rights are
## reserved.
##
## This software is supplied without any warranty or guaranteed support
## whatsoever. Neither the Broad Institute nor MIT can be responsible for its
## use, misuse, or functionality.



HscrSegFit <- function(h.seg.dat, theta, eps=1e-5, out.p=1e-3, min.iter=1, max.iter=10, force.diploid=FALSE, verbose=FALSE) {
   
   if (force.diploid) {
      min.iter = 1
   }
   
   if (verbose) {
      print(paste("OUT_P is", out.p))
   }
   theta <- AffyInitTheta(h.seg.dat=h.seg.dat, verbose)
   
    smms <- SegMeansMSteps(h.seg.dat, out.p, theta, eps, force.diploid, min.iter, max.iter, verbose=verbose)
            
   
   theta <- smms[["theta"]]
   h.snp.clust.p <- smms[["h.snp.clust.p"]]
   delta.tau <- smms[["delta.tau"]]
   
   delta.tau.sd <- BuildDeltaTauSd(h.seg.dat, delta.tau, out.p, theta, verbose=verbose)
   seg.log.ev <- BuildSegLogEv(h.seg.dat, theta, out.p, delta.tau, verbose=verbose)
   seg.expected.phase <- BuildSegExpectedPhase(length(h.seg.dat[["h.snp.d"]]), h.snp.clust.p)
   
   return(list(snp.clust.p=h.snp.clust.p, h.snp.gt.p=h.seg.dat[["h.snp.gt.p"]],
               delta.tau=delta.tau,
               delta.tau.sd=delta.tau.sd, sigma.h=smms[["sigma.h"]], loglik=smms[["loglik"]],
               seg.log.ev=seg.log.ev, seg.expected.phase=seg.expected.phase,
               theta=theta))
}

BuildSegExpectedPhase <- function(n.segs, h.snp.clust.p) {
  
  seg.expected.phase <- foreach (i = seq(n.segs), .combine=rbind) %dopar% {
    # i <- 1
    snp.clust.p <- h.snp.clust.p[[i]]
    state.mat <- matrix(c(0, 1, 2, 3), ncol=4, nrow=nrow(snp.clust.p), byrow=TRUE)
    snp.e.state <- rowSums(state.mat * snp.clust.p[, c(3, 2, 4, 1)])    
    ## now take expectation of phase over segment, weight by P(het)
    c( 
      sum(snp.clust.p[, 4] * snp.e.state) / sum(as.vector(snp.clust.p[, 4])), 
      sum(snp.clust.p[, 2] * snp.e.state) / sum(as.vector(snp.clust.p[, 2])) 
    )
  } 
  rownames(seg.expected.phase) <- NULL
  seg.expected.phase
}


BuildSegLogEv <- function(h.seg.dat, theta, out.p, delta.tau, verbose=verbose) {
  foreach(i = seq(length(h.seg.dat[["h.snp.d"]])), .combine=c) %dopar% {
    GetSegLogEv(i, h.seg.dat, theta, out.p, delta.tau=delta.tau[i,], verbose=verbose)[1]
  }
}

BuildDeltaTauSd <- function(h.seg.dat, delta.tau, out.p, theta, verbose=verbose) {
   h.mu.sd <- foreach(i = seq(length(h.seg.dat[["h.snp.d"]])), .combine=rbind) %dopar% {
      SegPostSdExtreme(h.seg.dat[["h.snp.d"]][[i]], h.seg.dat[["h.cn.d"]][[i]], delta.tau[i, ], out.p, h.seg.dat[["h.snp.gt.p"]][[i]], theta)
      
   }
   colnames(h.mu.sd) <- c("delta", "tau")
   rownames(h.mu.sd) <- NULL
   h.mu.sd
}


BuildHMuSdDEP <- function(h.d, h.e.mu, out.p, h.snp.gt.p, theta, verbose=verbose) {
  h.mu.sd <- foreach(i = seq(length(h.d)), .combine=rbind) %dopar% {
    SegPostSd(h.d[[i]], h.e.mu[i, ], out.p, h.snp.gt.p[[i]], theta)
  }
  colnames(h.mu.sd) <- c("delta", "tau")
  rownames(h.mu.sd) <- NULL
  h.mu.sd
}

SegMeansMSteps <- function(h.seg.dat, out.p, theta, eps, force.diploid, min.iter, max.iter, verbose=FALSE) {

   # h.seg.dat <- iams.res[["as.res"]][["h.seg.dat"]]
   # theta <- iams.res[["em.fit"]][["theta"]]
   # eps <- iams.res[["use.eps"]]
   # min.iter <- 1
   # max.iter <- 10

   n.segs <- length(h.seg.dat[[1]])
   if (verbose) {
      print(paste("h.d size =", n.segs))
   }
   h.ngt.t <- array(NA, dim=c(n.segs, 5))
   delta.tau <- InitDeltaAndTau(h.seg.dat, theta, seg.info, force.diploid)
   
   loglik <- -Inf  
   iter <- 1
   
   while (TRUE) {
      ##  M-steps for seg-means
      delta.tau <- OptimizeDeltaTauArray(delta.tau, h.seg.dat, out.p, theta, force.diploid, verbose=verbose)
      
      h.snp.clust.p <- ClustProbsESteps(h.seg.dat[["h.snp.d"]], delta.tau, h.seg.dat[["h.snp.gt.p"]], out.p, theta)
      for (i in seq(n.segs)) {
         h.ngt.t[i, ] <- colSums(h.snp.clust.p[[i]])
      }
      
      p.het <- CalculatePHet(h.ngt.t)
      
      theta <- HscrSegFitThetaOpt(iter, min.iter, p.het, h.seg.dat, delta.tau, out.p, theta, verbose=verbose)
      
      cur.loglik <- GetCurLogLik(h.seg.dat, delta.tau, out.p, theta)
      
      cond <- abs(cur.loglik - loglik) / abs(cur.loglik) 
      loglik <- cur.loglik
      sigma.h <- GetSigmaH(theta[["sigma.epsilon"]], theta[["sigma.eta"]])
      
      if (verbose) {
         print(round(cur.loglik, 4))
         PrintTheta(theta, cond)
      }
      
      
      if ((iter > min.iter) && ((cond < eps) || (iter >= max.iter))) {
         break
      }
      
      iter <- iter + 1
   }
   
   return(list(loglik=cur.loglik, theta=theta, delta.tau=delta.tau, sigma.h=sigma.h, h.snp.clust.p=h.snp.clust.p))
}


SegMeansMStepsDEP <- function(h.d, out.p, h.snp.gt.p, theta, eps, force.diploid, min.iter, max.iter, verbose=FALSE) {

  n.segs <- length(h.d)
  if (verbose) {
    print(paste("h.d size =", n.segs))
  }
  
  h.ngt.t <- array(NA, dim=c(n.segs, 5))
  h.e.mu <- InitHEMu(h.d, seg.info, force.diploid)
  
  loglik <- -Inf  
  iter <- 1
  
  while (TRUE) {
    ##  M-steps for seg-means
    h.e.mu <- OptimizeHEMu(h.e.mu, h.d, out.p, h.snp.gt.p, theta,
                           force.diploid, verbose=verbose)
    h.snp.clust.p <- ClustProbsESteps(h.d, h.e.mu, h.snp.gt.p,
                                      out.p, theta)
    for (i in seq(n.segs)) {
      h.ngt.t[i, ] <- colSums(h.snp.clust.p[[i]])
    }
    
    p.het <- CalculatePHet(h.ngt.t)
    
    theta <- HscrSegFitThetaOpt(iter, min.iter, p.het, h.d, h.snp.gt.p,
                                h.e.mu, h.snp.clust.p, out.p, theta,
                                verbose=verbose)
    
    cur.loglik <- GetCurLogLik(h.d, h.e.mu, out.p, h.snp.gt.p, theta)
    cond <- abs(cur.loglik - loglik) / abs(cur.loglik) 
    loglik <- cur.loglik
    sigma.h <- GetSigmaH(theta[["sigma.epsilon"]], theta[["sigma.eta"]])

    if (verbose) {
      print(round(cur.loglik, 4))
     # print(paste( "sigma_nu = ", round(theta$sigma.epsilon,4),
     #             ", sigma_eta = ", round(theta$sigma.eta, 4),
     #             ", het_cov = ", round(theta$het.cov,4),
     #             ", Nu = ", round(theta$nu,3),
     #             ", AT = ", round(theta$at,4), ", BG = ",
     #             round(theta$bg,4),
              
     #             ", sigma_h = ", round(sigma.h,4),
             #  ", cond = ", round(cond,7), sep="" ))
  
        PrintTheta(theta, cond)
    }
    
    
    if ((iter > min.iter) && ((cond < eps) || (iter >= max.iter))) {
      break
    }
    
    iter <- iter + 1
  }

  return(list(loglik=cur.loglik, theta=theta, h.e.mu=h.e.mu, sigma.h=sigma.h,
              h.snp.clust.p=h.snp.clust.p))
}


ClustProbsESteps <- function(h.d, delta.tau, h.snp.gt.p, out.p, theta) {
  ## E-steps for clust probs
  out <- foreach(i = seq(length(h.d))) %dopar% {
    EStep(h.d[[i]], delta.tau[i, ], h.snp.gt.p[[i]], out.p, theta)
  }

  return(out)
}

CalculatePHet <- function(h.ngt.t) {
  n.hom <- rowSums(h.ngt.t[, c(1, 3)])
  n.het <- rowSums(h.ngt.t[, c(2, 4)])
  
  return(sum(n.het) / sum(n.het + n.hom))
}

InitDeltaAndTau <- function(h.seg.dat, theta, seg.info, force.diploid) {
   
   ## just return delta and tau
   
    n.segs <- length(h.seg.dat[[1]])
   if (force.diploid) {
      h.e.mu <- array(NA, dim=c(n.segs, 3))
      for (i in seq(n.segs)) {
         h.e.mu[i, ] <- c(1, 2)
      }
   } else {
      init <- function(x) {
         d <- foreach(i=c("h.snp.d", "h.cn.d"), .combine=c) %do% {colSums(h.seg.dat[[i]][[x]])}
         out = median(d)
         out = ifelse(is.na(out), 2, out)
         return(median(out))   
      }
      h.mu.t <- unlist(lapply(1:n.segs, init))
      
      h.mu.t[h.mu.t < 0] <- 0
      i.mu.t <- h.mu.t
      quart <- i.mu.t / 4
      # h.e.mu <- cbind(quart, i.mu.t - quart, i.mu.t)
      
      delta = 2 * (i.mu.t - quart) - i.mu.t
      tau = i.mu.t
      dt = cbind(delta, tau)
   }
   return(dt)
}




InitHEMu <- function(h.d, seg.info, force.diploid) {
  n.segs <- length(h.d)
  if (force.diploid) {
    h.e.mu <- array(NA, dim=c(n.segs, 3))
    for (i in seq(n.segs)) {
      h.e.mu[i, ] <- c(1, 1, 2)
    }
  } else {
    h.mu.t <- unlist(lapply(lapply(h.d, colSums), median))
    h.mu.t[h.mu.t < 0] <- 0
    i.mu.t <- h.mu.t
    half <- i.mu.t / 2
    quart <- i.mu.t / 4
    h.e.mu <- cbind(quart, i.mu.t - quart, i.mu.t)
  }
  
  return(h.e.mu)
}

OptimizeDeltaTauArray <- function(delta.tau, h.seg.dat, out.p, theta, force.diploid, verbose=verbose) {

   # browser()
   if (verbose) print("Optimizing Array Delta and Tau")
   n.segs <- length(h.seg.dat[[1]])
   if (force.diploid) {
      delta.tau <- matrix(c(1, 2) + theta[["alpha"]], nrow=n.segs, ncol=2, byrow=TRUE)
   } else {
      # delta.tau <- foreach(i = seq(n.segs), .combine=rbind) %dopar% {
      #    res <- AffyPlatformSpecificOptimization(i, delta.tau, h.seg.dat, out.p, theta, verbose=verbose)
      #    if (verbose) cat("$")
      #    res
      # }

      delta.tau <- do.call('rbind', lapply(seq(n.segs), function(i) {
         res <- AffyPlatformSpecificOptimization(i, delta.tau, h.seg.dat, out.p, theta, verbose=verbose)
         if (verbose) cat("$")
         res
      }))

      rownames(delta.tau) <- NULL
      if (verbose) cat("\n")
   }
   return(delta.tau)
}


OptimizeHEMuArray <- function(h.e.mu, h.seg.dat, out.p, theta, force.diploid, verbose=verbose) {

   if (verbose) print("\n Optimizing Array HEMu")
   n.segs <- length(h.seg.dat[["h.snp.d"]])
   if (force.diploid) {
      h.e.mu <- matrix(c(1, 1, 2) + theta[["alpha"]], nrow=n.segs, ncol=3, byrow=TRUE)    
   } else {
      h.e.mu <- foreach(i = seq(n.segs), .combine=rbind) %dopar% {
#         i = 246
         res <- AffyPlatformSpecificOptimizationExtreme(i, h.e.mu, h.seg.dat, out.p, theta, verbose=verbose)
         if (verbose) cat("$")
         res
      }
      rownames(h.e.mu) <- NULL
      if (verbose) cat("\n")
   }
   return(h.e.mu)
}

OptimizeHEMu <- function(h.e.mu, h.d, out.p, h.snp.gt.p, theta, force.diploid, verbose=verbose) {
  n.segs <- length(h.d)

  if (force.diploid) {
    h.e.mu <- matrix(c(1, 1, 2) + theta[["alpha"]], nrow=n.segs,
                     ncol=3, byrow=TRUE)    
  } else {
##    h.e.mu <- foreach(i = seq(n.segs), .combine=rbind) %dopar% {
      ## we have a couple parameters to the optimization:
      ## h.d        -- the allele counts for each position (A and B)
      ## h.e.mu     -- the mu values for the segment
      ## out.p      -- ?
      ## h.snp.gt.p -- the snp priors
      ## theta      -- the theta start value 
    for (i in seq(n.segs)) {
      h.e.mu[i, ] <- PlatformSpecificOptimization(h.e.mu[i, ], h.d[[i]], out.p,
                                                  h.snp.gt.p[[i]], theta, verbose=verbose)
      if (verbose) {
        cat("$")
      }
    }
    ## foreach() leaves rownames, remove these
    rownames(h.e.mu) <- NULL
    if (verbose) {
      cat("\n")
    }
  }
  
  return(h.e.mu)
}

HscrSegFitThetaOpt <- function(iter, min.iter, p.het, h.seg.dat, delta.tau, out.p, theta, verbose=verbose) {
  ## wait for some small number of iterations to estimate variances;
  ## inits are usually close to correct.
  if (iter >= min.iter) {
    if (verbose) {
      print(paste(round(100 * p.het, 2), "% het", sep=""))
    }
    theta <- AffyThetaOpt(h.seg.dat, delta.tau, out.p, theta, verbose=verbose)
  }
  
  return(theta)
}


HscrSegFitThetaOptDEP <- function(iter, min.iter, p.het, h.d, h.snp.gt.p,
                               h.e.mu, h.snp.clust.p, out.p, theta,
                               verbose=verbose) {
  ## wait for some small number of iterations to estimate variances;
  ## inits are usually close to correct.
  if (iter >= min.iter) {
    if (verbose) {
      print(paste(round(100 * p.het, 2), "% het", sep=""))
    }
    theta <- ThetaOpt(h.d, h.snp.gt.p, h.e.mu, h.snp.clust.p,
                      out.p, theta, verbose=verbose)
  }

  return(theta)

}


GetCurLogLik <- function(h.seg.dat, delta.tau, out.p, theta) {
  n.segs <- length(h.seg.dat[["h.snp.d"]])
  
  seg.loglik <- foreach(i = seq(n.segs), .combine=rbind) %dopar% {
    c(sum(AffyCalcSnpLogLik(h.seg.dat[["h.snp.d"]][[i]], delta.tau[i, ], out.p, h.seg.dat[["h.snp.gt.p"]][[i]], theta)),
        sum(AffyCalcCnLogLik(h.seg.dat[["h.cn.d"]][[i]], delta.tau[i, ], out.p, theta) ))
  }  
  seg.loglik <- seg.loglik[complete.cases(seg.loglik)]
  
  return(sum(seg.loglik))
}

GetCurLogLikDEP <- function(h.d, h.e.mu, out.p, h.snp.gt.p, theta) {
  n.segs <- length(h.d)
  seg.loglik <- foreach(i = seq(n.segs), .combine=c) %dopar% {
    sum(AffyCalcSnpLogLik(h.d[[i]], h.e.mu[i, ], out.p, h.snp.gt.p[[i]],
                  theta))
  }

  return(sum(seg.loglik))
}

PrintTheta <- function(theta, cond, sigma.h=TRUE) {

   one = paste(sapply(names(theta), function(x) paste(x, "=", round(theta[[x]], 4), sep="")), collapse=", ")
   
   if (sigma.h) {
      sigma.h = GetSigmaH(theta[["sigma.epsilon"]], theta[["sigma.eta"]])
      two = paste(", sigma_h = ", round(sigma.h,4), ", cond = ", round(cond,7), sep="" )   
   } else {
      two = paste(", cond = ", round(cond,7), sep="" )   
   }
   
   print(paste(one, two))
}
