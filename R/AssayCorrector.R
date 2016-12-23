#' @title Print assay summary
#' @method print assay
#' @description \code{print.assay} simply prints a summary of the HTS assay
#' @param assay The assay you want to print
#' @param plate The plate number
#' @export
print.assay<-function(assay,plate=1){
  cat("HTS assay (",dim(assay$m)[1],"rows x ",dim(assay$m)[2],"columns x ",dim(assay$m)[3]," plates):\nPlate ",plate,"\n")
  print(assay$m[,,plate]) # Print first plate raw measurements
  cat("Minimum value: ",min(assay$m)," Maximum value: ",max(assay$m))
}
#' @title Plot assay plate-wise
#' @method plot assay
#' @description  \code{plot.assay} plots a hit map of the assay (only one plate at a time)
#' @param assay The assay you want to plot
#' @param plate The plate number
#' @param type Either "R" - raw assay, "C" - corrected assay (if it exists) or "P" - spatial bias position
#' @usage plot(assay,plate=2,type="P")
#' @export
plot.assay<-function(assay,plate=1,type="R"){
  rotate <- function(x) t(apply(x, 2, rev)) # Helper method to put rows back horizontally and columns vertically
  require(lattice)
  require(RColorBrewer)
  theme <- custom.theme(region=rev(brewer.pal(n=11, 'RdBu'))) # Custom red/blue theme
  if(type=="R")
    levelplot(rotate(assay$m[,,plate]),xlab="Columns",ylab="Rows",main=paste("Plate",plate,"raw measurements"),par.settings=theme,margin=F,pretty=T,scales=list(x=list(alternating=2,tck=c(0,0)),y=list(tck=c(0,0))))
  else if(type=="C" & 'mCorrected'%in%names(assay))
    levelplot(rotate(assay$mCorrected[,,plate]),xlab="Columns",ylab="Rows",main=paste("Plate",plate,"raw measurements"),par.settings=theme,margin=F,pretty=T,scales=list(x=list(alternating=2,tck=c(0,0)),y=list(tck=c(0,0))))
  else  if(type=="P")
    levelplot(rotate(assay$biasPositions[,,plate]),xlab="Columns",ylab="Rows",main=paste("Plate",plate,"raw measurements"),par.settings=theme,margin=F,pretty=T,scales=list(x=list(alternating=2,tck=c(0,0)),y=list(tck=c(0,0))))
  else
    stop("Error. Check your assay")
}
#' @title Create a new \code{assay}
#' @description \code{create} makes a new object of class assay. You should pass this object to detect() and correct() methods
#' @param m The assay you want to be corrected
#' @param ctrl An optional boolean array of the same dimensions as \code{m}. Each entry is 1 if the well is a control well, 0 otherwise. All control wells are excluded from all computations
#' @examples
#' m=array(20,c(8,12,5)) # Create array of 20s, 8 rows, 12 columns, 5 plates
#' m[1:5,12,]=40 # Introduce spatial bias in last column
#' m=m+rnorm(8*12*5) # Add random additive noise
#' assay=create(m)
#' @usage assay=create(m)
#' @export
create<-function(m,ctrl=NA){
  if(is.na(ctrl)){ # If no control pattern supplied, assuming none
    ctrl=m
    ctrl[,,]=0
  }
  if(any(!(ctrl%in%0:1))) # If non zero/one values detected
    stop("Control array must be binary")
  if(any(is.na(m)) || any(is.infinite(m))) # If values are missing or are infinite
    stop("NA in input assay")
  assay=NULL
  Rows=dim(m)[1]
  Columns=dim(m)[2]
  rownames(m)=if(Rows<=26)LETTERS[1:Rows]else{warning("Too many rows, naming them by numbers instead of letters.");sapply(1:Rows,toString)}
  colnames(m)=sapply(1:Columns,toString)
  rownames(ctrl)=rownames(m)
  colnames(ctrl)=colnames(m)
  assay$m=m
  assay$ctrl=ctrl
  assay$biasType=NULL
  biasPositions=ctrl
  biasPositions[,,]=0
  assay$biasPositions=biasPositions
  assay$mCorrected=biasPositions
  class(assay)="assay"
  return(assay)
}
#' @title Detect the type of bias present in the assay
#' @description \code{detect} implements both the additive and multiplicative PMP methods
#' @param assay The assay to be corrected. Has to be an \code{assay} object.
#' @param alpha Significance level threshold (defaults to 0.05)
#' @param type \code{P}:plate-specific, \code{A}:assay-specific, \code{PA}:plate then assay-specific, \code{AP}:assay then plate-specific
#' @return The corrected assay (\code{assay} object)
#' @usage detect(assay,method=1,alpha=0.01,type="P")
#' @export
detect<-function(assay,method=1,alpha=0.05,type="PA"){
  m=assay$m
  ctrl=assay$ctrl
  biasType=assay$biasType
  m.additive=ctrl # Initialize empty additive assay
  m.multiplicative=ctrl # Initialize empty multiplicative assay
  dimensions=dim(m)
  Depth=dimensions[3]
  if(type=="AP") # If we want assay->plate correction, first apply assay-wise correction
    m=.assay(m,ctrl,alpha)
  for (k in 1:Depth){
    m.additive[,,k]=try(.PMP(m[,,k],ctrl[,,k],1,alpha)) # Correct the plate k using aPMP
    m.multiplicative[,,k]=try(.PMP(m[,,k],ctrl[,,k],2,alpha)) # Correct the plate k using mPMP
    if(class(m.additive[,,k])=="try-error" || class(m.multiplicative[,,k])=="try-error")
      stop("PMP encountered a problem") # Problem in PMP - check your data
    mww=(m.additive[,,k]!=m[,,k])*1 # Determine which rows and columns the Mann-Whitney test detected as biased (both technologies have same bias locations, hence using additive)
    assay$biasPositions[,,k]=mww # Save the bias positions suggested by the Mann-Whitney test
    biased.additive=list()
    biased.multiplicative=list()
    unbiased=list()
    for(i in 1:dimensions[1]){
      for(j in 1:dimensions[2]){
        if(mww[i,j]&!ctrl[i,j,k]){ # If the MW test flaged this row/column AND this cell is not a control well
          biased.additive=c(biased.additive,m.additive[i,j,k]) # Add well (i,j) corrected by aPMP to set of corrected wells
          biased.multiplicative=c(biased.multiplicative,m.multiplicative[i,j,k]) # Add well corrected by aPMP to set of corrected wells
        }
        else if(!mww[i,j]&!ctrl[i,j,k]) # If the MW did not flag this row/column AND this cell is not a control well
          unbiased=c(unbiased,m.additive[i,j,k]) # Add this well to set of unbiased wells
      }
    }
    biased.additive=unlist(biased.additive)
    biased.multiplicative=unlist(biased.multiplicative)
    unbiased=unlist(unbiased)
    pvalue.additive=ks.test(biased.additive,unbiased)$p.value
    pvalue.multiplicative=ks.test(biased.multiplicative,unbiased)$p.value
    if(pvalue.additive > alpha & pvalue.multiplicative < alpha) # aPMP did better
      biasType[k]='A'
    if(pvalue.additive < alpha & pvalue.multiplicative > alpha) # mPMP did better
      biasType[k]='M'
    if(pvalue.additive < alpha & pvalue.multiplicative < alpha) # undetermined, both are bad
      biasType[k]='U'
    if(pvalue.additive > alpha & pvalue.multiplicative > alpha) # undetermined, both are good
      biasType[k]='U'
  }
  assay$biasType=biasType # Write the resulting vector back
  return(assay)
}
#' @title Correct the bias present in the assay, previously detected by the \code{detect} method
#' @description \code{correct} uses either the additive and multiplicative PMP methods to correct the assay measurements
#' @param assay The assay to be corrected. Has to be an \code{assay} object.
#' @param method \code{NULL}:autodetect (default), \code{1}:additive, \code{2}:multiplicative
#' @param alpha Significance level threshold (defaults to 0.05)
#' @param type \code{P}:plate-specific, \code{A}:assay-specific, \code{PA}:plate then assay-specific, \code{AP}:assay then plate-specific
#' @return The corrected assay (\code{assay} object)
#' @usage correct(assay,method=NULL,alpha=0.01,type="PA")
#' @export
correct<-function(assay,method=NULL,alpha=0.05,type="PA"){
  m=assay$m
  ctrl=assay$ctrl
  biasType=assay$biasType
  dimensions=dim(m)
  Depth=dimensions[3]
  if(is.null(biasType))
    stop("Run detect() first.")
  mCorrected=m # Initialize the corrected assay to the raw one
  if(type=="P"){
    for (k in 1:Depth){
      if(!is.null(method)) # Correct using given method
        mCorrected[,,k]=try(.PMP(m[,,k],ctrl[,,k],method,alpha))
      else{ # Autodetect method for each plate
        if(biasType[k]=='A')
          mCorrected[,,k]=try(.PMP(m[,,k],ctrl[,,k],1,alpha))
        if(biasType[k]=='M')
          mCorrected[,,k]=try(.PMP(m[,,k],ctrl[,,k],2,alpha))
        # else, if the bias is undefined, we cannot apply the correction algorithm, so we skip it
      }
    }
  }
  else if(type=="A"){
    mCorrected=.assay(m,ctrl,alpha)
  }
  else if(type=="PA"){
    # Part 1: Plate-wise
    for (k in 1:Depth){
      if(!is.null(method)) # Correct using given method
        mCorrected[,,k]=try(.PMP(m[,,k],ctrl[,,k],method,alpha))
      else{ # Autodetect method for each plate
        if(biasType[k]=='A')
          mCorrected[,,k]=try(.PMP(m[,,k],ctrl[,,k],1,alpha))
        if(biasType[k]=='M')
          mCorrected[,,k]=try(.PMP(m[,,k],ctrl[,,k],2,alpha))
        # else, if the bias is undefined, we cannot apply the correction algorithm, so we skip it
      }
    }
    # Part 2: Assay-wise
    mCorrected=.assay(m,ctrl,alpha)
  }
  else if(type=="AP"){
    # Part 1: Assay-wise
    mCorrected=.assay(m,ctrl,alpha)
    # Part 2: Plate-wise
    for (k in 1:Depth){
      if(!is.null(method)) # Correct using given method
        mCorrected[,,k]=try(.PMP(m[,,k],ctrl[,,k],method,alpha))
      else{ # Autodetect method for each plate
        if(biasType[k]=='A')
          mCorrected[,,k]=try(.PMP(m[,,k],ctrl[,,k],1,alpha))
        if(biasType[k]=='M')
          mCorrected[,,k]=try(.PMP(m[,,k],ctrl[,,k],2,alpha))
        # else, if the bias is undefined, we cannot apply the correction algorithm, so we skip it
      }
    }
  }
  else{
    stop("Unknown correction type.")
  }
  assay$mCorrected=mCorrected
  return(assay)
}