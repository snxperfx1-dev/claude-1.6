//+------------------------------------------------------------------+
//|                                                   Letra37_EA.mq5  |
//|        Fully-tradeable Expert Advisor built on the Letra 37       |
//|        decision engine (shared Letra37_Engine.mqh).              |
//|                                                                  |
//|  The EA recomputes the full multi-engine pipeline on every new   |
//|  bar of the chart timeframe, reads the V72 / engine decision for |
//|  the last CLOSED bar, and manages live trades:                   |
//|    - risk-based or fixed position sizing                          |
//|    - SL from the Invalidation engine / ATR / fixed                |
//|    - TP from the Target engine (TP1/TP2) / RR / ATR               |
//|    - partial close, break-even, ATR/point trailing                |
//|    - exits on opposite signal / invalidation / phase change       |
//|    - session filter, spread guard, daily-loss & max-trades guard  |
//+------------------------------------------------------------------+
#property copyright "Letra 37 EA (engine port)"
#property version   "1.00"
#property description "Order-placing EA driven by the Letra 37 wave-intelligence / V72 decision engine."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>

//===================================================================
//  ENGINE (inlined from Letra37_Engine.mqh)
//===================================================================
//+------------------------------------------------------------------+
//| Letra37_Engine.mqh                                               |
//| Shared analytical engine for the Letra 37 port.                  |
//| Included by both Letra37.mq5 (indicator) and Letra37_EA.mq5 (EA).|
//| Contains: all inputs, the multi-timeframe structure/physics/     |
//| belief/FU engines, the full chart-TF intelligence pipeline,      |
//| ERF, FRZ, and the V72 decision architecture.                     |
//+------------------------------------------------------------------+
//==================================================================
// ENUMS (replicating Pine string-option inputs)
//==================================================================
enum ENUM_DISPLAY_MODE { DM_EXECUTION, DM_CONTEXT, DM_RESEARCH };
enum ENUM_ORIGIN_MODE  { OM_NONE, OM_SHORT, OM_LONG, OM_BOTH };
enum ENUM_TXT_SIZE     { TS_TINY, TS_SMALL, TS_NORMAL };
enum ENUM_PANEL_POS    { PP_TOP, PP_MIDDLE, PP_BOTTOM };

//==================================================================
// SECTION 1 -- INPUTS (ported 1:1 from the Pine source)
//==================================================================

//--- Dashboard panel toggles -------------------------------------
input group "Dashboard A - Command Center"
input bool showDA_Header      = true;
input bool showDA_Directive   = true;
input bool showDA_WaveCtx     = true;
input bool showDA_MarketState = true;
input bool showDA_HTFStack    = true;
input bool showDA_Physics     = true;

input group "Dashboard B - Belief Distributions"
input bool showDB_Header   = true;
input bool showDB_Beliefs  = true;
input bool showDB_Proximity= true;
input bool showDB_ConvEvid = true;
input bool showDB_PhysObs  = true;
input bool showDB_Geometry = true;

input group "Dashboard C - Intelligence Engine"
input bool showDC_Header     = true;
input bool showDC_Hypothesis = true;
input bool showDC_Prediction = true;
input bool showDC_Validation = true;
input bool showDC_AdapConf   = true;
input bool showDC_M1Warn     = true;
input bool showDC_Quality    = true;
input bool showDC_DirProb    = true;
input bool showDC_LiveOpp    = true;
input bool showDC_Execution  = true;

input group "Dashboard P3 - Recursive Wave Intel"
input bool showDP3_Header       = true;
input bool showDP3_Narrative    = true;
input bool showDP3_Nested       = true;
input bool showDP3_Dominance    = true;
input bool showDP3_Fusion       = true;
input bool showDP3_Agreement    = true;
input bool showDP3_FractalConf  = true;
input bool showDP3_Cycles       = true;
input bool showDP3_GeoCap       = true;
input bool showDP3_ExecProb     = true;
input bool showDP3_WaveProgress = true;

input group "Dashboard FU - FU Order Blocks"
input bool showDFU_Panel    = true;
input bool showDFU_Header   = true;
input bool showDFU_Stats    = true;
input bool showDFU_LastBlock= true;

//--- Section 9 entry-cycle visibility ----------------------------
input group "Entry Cycle Visibility (Section 9)"
input bool ecvSupply         = true;
input bool ecvDemand         = true;
input bool ecvHighs          = true;
input bool ecvLows           = true;
input bool ecvExpansion      = true;
input bool ecvPreConvexity   = true;
input bool ecvConvexity      = true;
input bool ecvAbsorption     = true;   // SPEC: renamed conceptually to "Transition Environment" (recursive depth/CHOCH/compression/failure/dominance)
input bool ecvRetracement    = true;
input bool ecvInduction      = true;
input bool ecvLiquidation    = true;
input bool ecvFUCandle       = true;
input bool ecvImbalance      = true;
input bool ecvFUImbalance    = true;
input bool ecvOrigin         = true;
input bool ecvWaveCompletion = true;
input bool ecvAllLocations   = false;

//--- Core --------------------------------------------------------
input group "Core Settings"
input int   pivotLen  = 5;
input int   atrLen    = 14;
input int   effLen    = 10;
input int   resetBars = 20;

//--- Filters -----------------------------------------------------
input group "Displacement & Filters"
input double impulseAtrMult = 1.5;
input double retrMin        = 0.3;
input double retrMax        = 0.8;
input double effThresh      = 0.65;
input double dispThresh     = 1.5;
input double convMult       = 0.01;
input int    acceptBars     = 2;
input int    obLookback     = 8;
input int    obMaxBars      = 50;

//--- Structure ---------------------------------------------------
input group "Market Structure"
input bool   useStrictStructure = true;
input int    structLen          = 10;
input bool   showStruct         = true;
input bool   requireStruct      = true;
input double chochBufferATR     = 0.75;

//--- Inducement --------------------------------------------------
input group "Inducement Engine"
input int    inducLookback    = 80;
input double inducZoneWidth   = 0.25;
input bool   requirePreConv   = true;
input bool   requireInduction = true;
input bool   showInducZone    = true;
input bool   showInducLabels  = true;

//--- Liquidity ---------------------------------------------------
input group "Liquidity Engine"
input double liqRadius        = 0.25;
input double liqAgDecay       = 0.95;
input bool   showLiq          = true;
input bool   requireLiqSweep  = true;
input int    liqSweepLookback = 10;

//--- MTF ---------------------------------------------------------
input group "Multi-Timeframe"
input ENUM_TIMEFRAMES tf1 = PERIOD_M15;   // Timeframe 1 (HTF Bias)
input ENUM_TIMEFRAMES tf2 = PERIOD_H1;    // Timeframe 2 (HTF Bias)

//--- Execution ---------------------------------------------------
input group "Execution Controls"
input int    baseLockBars    = 10;
input bool   requireHTFAlign = false;
input double execThreshold   = 5.0;

//--- Visuals -----------------------------------------------------
input group "Visuals"
input bool             showFlipzone     = true;
input bool             showLabels       = true;
input bool             showSignals      = true;
input bool             showTable        = true;
input bool             showSDZones      = true;
input bool             showP4Box        = true;
input bool             showCycleHistory = true;
input ENUM_ORIGIN_MODE originMode       = OM_NONE;
input ENUM_TXT_SIZE    dashTextSize     = TS_SMALL;
input bool             zoneFillOn       = false;

//--- Intelligence engine -----------------------------------------
input group "Intelligence Engine"
input int    beliefSmooth      = 3;
input double confDecayRate     = 0.02;
input double devReinterpThresh = 30.0;

//--- FU order block inputs ---------------------------------------
input group "FU Order Blocks"
input bool   showFUBlocks    = true;
input bool   showFULabels    = true;
input int    fuLookback      = 3;
input double fuMinBodyRatio  = 0.6;
input double fuMinWickRatio  = 0.25;
input int    fuMaxBarsActive = 75;
input bool   fuRequireInZone = true;
input bool   fuBoostBelief   = true;
input bool   fuAlertOn       = true;
input bool   showFUWick      = true;
input int    fuwLookback     = 5;
input double fuwMinWickFrac  = 0.5;
input int    fuAuthMin       = 40;

//--- Display intelligence engine ---------------------------------
input group "Display Intelligence Engine"
input ENUM_DISPLAY_MODE displayMode      = DM_EXECUTION;
input bool   showFUConflLabel = true;
input bool   showFULifecycle  = true;
input bool   enableClustering = true;
input int    clusterWindow    = 8;
input bool   showNarrative    = true;
input bool   showDIE_Dashboard= true;

//--- Future return zones -----------------------------------------
input group "Future Return Zones (Section 17/18)"
input bool   showFRZ           = true;
input bool   showFRZ_Labels    = true;
input bool   showFRZ_Dashboard = true;
input int    frz_minScore      = 26;
input int    frz_maxBarsActive = 100;

//--- Energy resolution framework ---------------------------------
input group "Energy Resolution Framework (ERF)"
input bool   showERF_Dashboard = true;
input double erfReadyResW      = 0.25;
input double erfReadyResidW    = 0.20;
input double erfReadyConfW     = 0.15;
input double erfEntryThreshold = 45.0;
input bool   erfGateEnabled    = true;
input bool   showEntryZone     = true;
input double entryZoneWidthA   = 0.15;

//--- V72 decision dashboard --------------------------------------
input group "V72 - Decision Dashboard"
input bool            in_dashAdvancedMode = false;
input bool            in_showV72Command   = true;
input ENUM_PANEL_POS  commandPanelYOffset = PP_BOTTOM;
input bool            showV72Destination  = true;
input bool            showV72RevDest      = false;

input group "V72 - Trade Qualification (TQE)"
input double in_frzProximityATR   = 2.0;
input double in_frzConvergenceATR = 0.5;
input double in_tqeW_ie1a = 0.25;
input double in_tqeW_erf  = 0.15;
input double in_tqeW_frz  = 0.15;
input double in_tqeW_mce  = 0.20;
input double in_tqeW_re   = 0.10;
input double in_tqeW_liq  = 0.15;
input double in_tqeGradeA1= 85.0;
input double in_tqeGradeA = 72.0;
input double in_tqeGradeB = 58.0;
input double in_tqeGradeC = 42.0;

input group "V72 - Rotation Intelligence (RIE)"
input double in_rieW_decay   = 0.35;
input double in_rieW_absorb  = 0.30;
input double in_rieW_convex  = 0.20;
input double in_rieW_stabExp = 0.40;
input double in_rieW_press   = 0.50;
input double in_rieW_stabInv = 0.30;

input group "V72 - Multi-TF Consensus (MCE)"
input ENUM_TIMEFRAMES mce_tf3 = PERIOD_H4;  // MCE TF3 (HTF)
input ENUM_TIMEFRAMES mce_tf4 = PERIOD_D1;  // MCE TF4 (HTF)

input group "V72 - Target / Invalidation"
input double in_invOriginBuffer = 0.25;
input double in_invZoneBuffer   = 0.10;
input double in_teTertiaryATR   = 2.0;
input double in_rrMinimum       = 1.5;
input bool   in_teTertiaryOn    = false;

input group "V72 - Decision Output (DOE)"
input int    in_doeCapBase = 88;
input int    in_doeCapConv = 95;

//--- Derived origin flags ----------------------------------------
bool showOriginShort;   // set in OnInit
bool showOriginLong;


//==================================================================
// NA SENTINEL + MATH HELPERS (replicating Pine na / ta.* on series)
//==================================================================
#define NA  DBL_MAX

bool   naf(const double x){ return(x==DBL_MAX || x!=x); }
double nz(const double x, const double rep=0.0){ return(naf(x)? rep : x); }
double fmin2(const double a,const double b){ return(a<b?a:b); }
double fmax2(const double a,const double b){ return(a>b?a:b); }
double clamp(const double v,const double lo,const double hi){ return(v<lo?lo:(v>hi?hi:v)); }
int    iclamp(const int v,const int lo,const int hi){ return(v<lo?lo:(v>hi?hi:v)); }

//--- EMA over an oldest->newest array ----------------------------
void EMAarr(const double &src[], double &dst[], const int period)
{
   int n=ArraySize(src); ArrayResize(dst,n);
   if(n==0) return;
   double a=2.0/(period+1.0);
   dst[0]=src[0];
   for(int j=1;j<n;j++) dst[j]=dst[j-1]+a*(src[j]-dst[j-1]);
}

//--- SMA -----------------------------------------------------------
void SMAarr(const double &src[], double &dst[], const int period)
{
   int n=ArraySize(src); ArrayResize(dst,n);
   double run=0;
   for(int j=0;j<n;j++){
      run+=src[j];
      if(j>=period) run-=src[j-period];
      int cnt=(j+1<period)?(j+1):period;
      dst[j]=run/cnt;
   }
}

//--- ATR (Wilder RMA of true range) -------------------------------
void ATRarr(const double &h[], const double &l[], const double &c[], double &dst[], const int period)
{
   int n=ArraySize(c); ArrayResize(dst,n);
   if(n==0) return;
   double tr;
   double prevRMA=0; double seedSum=0;
   for(int j=0;j<n;j++){
      if(j==0) tr=h[0]-l[0];
      else tr=fmax2(h[j]-l[j], fmax2(MathAbs(h[j]-c[j-1]), MathAbs(l[j]-c[j-1])));
      if(j<period){ seedSum+=tr; dst[j]=seedSum/(j+1); prevRMA=dst[j]; }
      else { prevRMA=(prevRMA*(period-1)+tr)/period; dst[j]=prevRMA; }
   }
}

//--- pivot high/low: value emitted at bar (center+len), else NA ----
void PivotHigh(const double &h[], double &dst[], const int len)
{
   int n=ArraySize(h); ArrayResize(dst,n); ArrayInitialize(dst,NA);
   for(int j=2*len;j<n;j++){
      int ctr=j-len; double v=h[ctr]; bool piv=true;
      for(int k=ctr-len;k<=ctr+len && piv;k++){ if(k==ctr) continue; if(h[k]>=v) piv=false; }
      if(piv) dst[j]=v;
   }
}
void PivotLow(const double &l[], double &dst[], const int len)
{
   int n=ArraySize(l); ArrayResize(dst,n); ArrayInitialize(dst,NA);
   for(int j=2*len;j<n;j++){
      int ctr=j-len; double v=l[ctr]; bool piv=true;
      for(int k=ctr-len;k<=ctr+len && piv;k++){ if(k==ctr) continue; if(l[k]<=v) piv=false; }
      if(piv) dst[j]=v;
   }
}

//--- helpers used inside engines ----------------------------------
double SumAbsDiff(const double &c[], const int j, const int len)
{
   double s=0; for(int k=0;k<len;k++){ int a=j-k, b=j-k-1; if(b<0) break; s+=MathAbs(c[a]-c[b]); } return(s);
}
double HighestPrior(const double &h[], const int j, const int len)
{ // max over [j-len .. j-1]   == ta.highest(h,len)[1]
   double m=-DBL_MAX; for(int k=1;k<=len;k++){ int idx=j-k; if(idx<0) break; if(h[idx]>m) m=h[idx]; } return(m==-DBL_MAX?NA:m);
}
double LowestPrior(const double &l[], const int j, const int len)
{
   double m=DBL_MAX; for(int k=1;k<=len;k++){ int idx=j-k; if(idx<0) break; if(l[idx]<m) m=l[idx]; } return(m==DBL_MAX?NA:m);
}
double HighestN(const double &h[], const int j, const int len)
{
   double m=-DBL_MAX; for(int k=0;k<len;k++){ int idx=j-k; if(idx<0) break; if(h[idx]>m) m=h[idx]; } return(m==-DBL_MAX?NA:m);
}
double LowestN(const double &l[], const int j, const int len)
{
   double m=DBL_MAX; for(int k=0;k<len;k++){ int idx=j-k; if(idx<0) break; if(l[idx]<m) m=l[idx]; } return(m==DBL_MAX?NA:m);
}

//==================================================================
// PER-TIMEFRAME RATES CONTAINER + LOADER
//==================================================================
struct TFData
{
   datetime t[];
   double   o[], h[], l[], c[];
   double   vol[];
   int      n;
};

bool LoadTF(const ENUM_TIMEFRAMES tf, const int bars, TFData &d)
{
   MqlRates r[];
   ArraySetAsSeries(r,false);
   int got=CopyRates(_Symbol, tf, 0, bars, r);
   if(got<=0){ d.n=0; return(false); }
   d.n=got;
   ArrayResize(d.t,got); ArrayResize(d.o,got); ArrayResize(d.h,got);
   ArrayResize(d.l,got); ArrayResize(d.c,got); ArrayResize(d.vol,got);
   for(int i=0;i<got;i++){
      d.t[i]=r[i].time; d.o[i]=r[i].open; d.h[i]=r[i].high;
      d.l[i]=r[i].low;  d.c[i]=r[i].close; d.vol[i]=(double)r[i].tick_volume;
   }
   return(true);
}

//--- f_safeTF: clamp a requested TF up to chart TF when chart>H1 ---
ENUM_TIMEFRAMES SafeTF(const ENUM_TIMEFRAMES req)
{
   int chartSec=PeriodSeconds(_Period);
   if(chartSec>3600 && PeriodSeconds(req)<chartSec) return(_Period);
   return(req);
}

//==================================================================
// STRUCTURE ENGINE  (f_se) -- full 18-output state machine per TF
//==================================================================
struct SEOut
{
   datetime t[];
   int    n;
   double dir[], ph[], sh[], sl[], psh[], psl[], bos[], ch[];
   double p4h[], p4l[], inv[], tgt[], ft[], fb[], fs[], wp[], cm[], mf[], dom[], comp[], rec[], recReq[];
};

void ComputeSE(const ENUM_TIMEFRAMES tfReq, const int bars,
               const int pvLen, const int stLen, const int atrL,
               const double effT, const double dispT, const double convM,
               const double impM, const double chBuf, const int effL,
               SEOut &O)
{
   ENUM_TIMEFRAMES tf=SafeTF(tfReq);
   TFData d; if(!LoadTF(tf,bars,d) || d.n<2*pvLen+5){ O.n=0; return; }
   int n=d.n;

   //--- precompute series ---
   double diff[]; ArrayResize(diff,n); diff[0]=0; for(int j=1;j<n;j++) diff[j]=d.c[j]-d.c[j-1];
   double vel[]; EMAarr(diff,vel,3);
   double acc[]; ArrayResize(acc,n); acc[0]=0; for(int j=1;j<n;j++) acc[j]=vel[j]-vel[j-1];
   double cvx[]; ArrayResize(cvx,n); cvx[0]=0; for(int j=1;j<n;j++) cvx[j]=acc[j]-acc[j-1];
   double csm[]; EMAarr(cvx,csm,3);
   double atr[]; ATRarr(d.h,d.l,d.c,atr,atrL);
   double phA[]; PivotHigh(d.h,phA,pvLen);
   double plA[]; PivotLow(d.l,plA,pvLen);

   //--- outputs ---
   O.n=n; ArrayResize(O.t,n);
   ArrayResize(O.dir,n); ArrayResize(O.ph,n); ArrayResize(O.sh,n); ArrayResize(O.sl,n);
   ArrayResize(O.psh,n); ArrayResize(O.psl,n); ArrayResize(O.bos,n); ArrayResize(O.ch,n);
   ArrayResize(O.p4h,n); ArrayResize(O.p4l,n); ArrayResize(O.inv,n); ArrayResize(O.tgt,n);
   ArrayResize(O.ft,n);  ArrayResize(O.fb,n);  ArrayResize(O.fs,n);  ArrayResize(O.wp,n);
   ArrayResize(O.cm,n);  ArrayResize(O.mf,n);  ArrayResize(O.dom,n); ArrayResize(O.comp,n); ArrayResize(O.rec,n); ArrayResize(O.recReq,n);

   //--- state (var) ---
   double curSH=NA,curSL=NA,prSH=NA,prSL=NA;
   double lastP=NA,prevP=NA; int lastD=0,prevD=0;
   int    dir=0; double ftv=NA,fbv=NA,p4h=NA,p4l=NA,inv=NA,tgt=NA,cycH=NA,cycL=NA;
   bool   bos1=false,bos2=false; double protSw=NA,protSw2=NA,indOrig=NA,indExt=NA; bool indBrk=false;
   int    lastDirSeen=0; int phaseState=0; int recBrk=0; bool recArm=true;

   for(int j=0;j<n;j++){
      O.t[j]=d.t[j];
      double cl=d.c[j], op=d.o[j], hi=d.h[j], lo=d.l[j];
      double A=atr[j];
      double mv=(j>=effL)?MathAbs(cl-d.c[j-effL]):0.0;
      double ps=SumAbsDiff(d.c,j,effL);
      double eff=(ps>0)?mv/ps:0.0;
      double disp=(hi-lo)/fmax2(A,1e-10);
      double velP=(j>0)?vel[j-1]:0, accP=(j>0)?acc[j-1]:0, accP2=accP;
      bool bullImp=eff>effT && vel[j]>velP && acc[j]>0 && cl>op && disp>dispT;
      bool bearImp=eff>effT && vel[j]<velP && acc[j]<0 && cl<op && disp>dispT;
      bool bullDec=MathAbs(acc[j])<MathAbs(accP)*0.8 && vel[j]>0;
      bool bearDec=MathAbs(acc[j])<MathAbs(accP)*0.8 && vel[j]<0;

      double pH=phA[j], pL=plA[j];
      //--- swings ---
      if(!naf(pH)){ prSH = naf(curSH)?pH:curSH; curSH=pH; }
      if(!naf(pL)){ prSL = naf(curSL)?pL:curSL; curSL=pL; }
      //--- pivot memory ---
      double eP=NA; int eD=0;
      if(!naf(pH)){ eP=pH; eD=1; } else if(!naf(pL)){ eP=pL; eD=-1; }
      if(eD!=0){ prevP=lastP; prevD=lastD; lastP=eP; lastD=eD; }
      //--- BOS/CHoCH ---
      bool bullBOS=!naf(prSH) && cl>prSH;
      bool bearBOS=!naf(prSL) && cl<prSL;
      bool bullCH =!naf(prSH) && cl>prSH+A*chBuf;
      bool bearCH =!naf(prSL) && cl<prSL-A*chBuf;
      //--- impulse ---
      bool eLong =!naf(pH) && prevD==-1 && (pH-prevP)>A*impM;
      bool eShort=!naf(pL) && prevD==1  && (prevP-pL)>A*impM;
      //--- direction / point4 / invalidation / target ---
      bool hasCtx=dir!=0 && !naf(ftv);
      bool flipDn=dir==1  && bearCH;
      bool flipUp=dir==-1 && bullCH;
      bool isRev=(eLong && dir==-1)||(eShort && dir==1)||flipUp||flipDn;
      bool spawn=(eLong||eShort||flipUp||flipDn) && (!hasCtx||isRev);
      if(spawn){
         int nd = eLong?1: eShort?-1: flipUp?1:-1;
         double _hi=fmax2(lastP,prevP), _lo=fmin2(lastP,prevP);  // v60 DIR-FIX: order OB by price, not pivot recency
         double obT=_hi, obB=_lo;
         dir=nd; ftv=obT; fbv=obB; p4h=obT; p4l=obB; cycH=hi; cycL=lo;
         inv = nd==1?_lo:_hi;                                     // invalidation pinned to the protective extreme
         double rng=(!naf(prSH)&&!naf(prSL))?MathAbs(prSH-prSL):A*5.0;
         tgt = nd==1? nz(obT,cl)+rng : nz(obB,cl)-rng;
      }
      if(dir==1)  cycH=naf(cycH)?hi:fmax2(cycH,hi);
      if(dir==-1) cycL=naf(cycL)?lo:fmin2(cycL,lo);

      int bosOut=bullBOS?1:(bearBOS?-1:0);
      int chOut =bullCH?1:(bearCH?-1:0);

      //--- lifecycle ---
      bool reset=(dir!=lastDirSeen); lastDirSeen=dir;
      if(reset){ bos1=false; bos2=false; protSw=NA; protSw2=NA; indOrig=NA; indExt=NA; indBrk=false; }
      if(dir==1 && !naf(pL)){ protSw2=protSw; protSw=pL; }
      if(dir==-1 && !naf(pH)){ protSw2=protSw; protSw=pH; }
      bool oppBOS=(dir==1 && !naf(protSw) && cl<protSw)||(dir==-1 && !naf(protSw) && cl>protSw);
      if(!bos1 && oppBOS){ bos1=true; indOrig = dir==1?nz(cycH,hi):nz(cycL,lo); }
      if(bos1 && !bos2 && oppBOS && !naf(protSw2) && (dir==1? cl<protSw2 : cl>protSw2)) bos2=true;
      if(bos1 && dir==1)  indExt=naf(indExt)?cl:fmin2(indExt,cl);
      if(bos1 && dir==-1) indExt=naf(indExt)?cl:fmax2(indExt,cl);
      if(bos2 && !naf(indOrig)){
         if(dir==1 && cl>indOrig) indBrk=true;
         if(dir==-1 && cl<indOrig) indBrk=true;
      }

      double convScore=fmin2(MathAbs(csm[j])/fmax2(A*convM,1e-10)*50.0,100.0);
      double expScore =fmin2(eff/fmax2(effT,1e-10)*50.0 + disp/fmax2(dispT,1e-10)*50.0,100.0);
      double absScore =(eff<effT*0.7 && MathAbs(vel[j])<MathAbs(velP)*0.6)?60.0+convScore*0.4:convScore*0.3;
      bool momExpStrong=eff>effT*0.75 && (dir==1?vel[j]>0:vel[j]<0);
      bool momDecaying =dir==1?bullDec:bearDec;
      bool momCounter  =dir==1?bearImp:bullImp;
      bool momExhaust  =eff<effT*0.65 && absScore>40.0;
      bool physConvexDevel=convScore>35.0;
      bool physTransfer   =convScore>48.0 || absScore>40.0;
      bool physCapacityLow=absScore>45.0 || eff<effT*0.6;

      //--- v60 wave geometry + compression / recursion / dominance ---
      int wdir = !naf(inv)?(cl>inv?1:(cl<inv?-1:dir)):dir;
      bool atFlip=!naf(ftv)&&!naf(fbv)&&cl<=ftv&&cl>=fbv;
      bool expanding=momExpStrong||eLong||eShort||(wdir==1?bullImp:bearImp);
      bool atExtreme=wdir==1?hi>=nz(cycH,hi):(wdir==-1?lo<=nz(cycL,lo):false);
      double extr=wdir==1?nz(cycH,cl):nz(cycL,cl);
      bool extended=!naf(inv)&&MathAbs(extr-inv)>A*1.5;
      double fzMid=(!naf(ftv)&&!naf(fbv))?(ftv+fbv)/2.0:NA;
      double retrFrac=(!naf(fzMid)&&MathAbs(extr-fzMid)>1e-10)?MathAbs(extr-cl)/MathAbs(extr-fzMid):0.0;
      double compIdx=fmin2(100.0,fmax2(0.0,(1.0-fmin2(disp/fmax2(dispT,1e-10),1.0))*60.0+(1.0-fmin2(eff/fmax2(effT,1e-10),1.0))*40.0));
      bool phase2CH=(dir==1&&bearCH)||(dir==-1&&bullCH);
      if(reset||(atExtreme&&extended)){ recBrk=0; recArm=true; }
      if((dir==1&&!naf(pH))||(dir==-1&&!naf(pL))) recArm=true;
      if((phase2CH||oppBOS)&&recArm&&!atExtreme){ recBrk++; recArm=false; }
      //--- SPEC-CORRECT compression -> recursion mapping ---
      // "High compression: New High -> small failures -> many recursive cycles -> transition"
      // "Low compression: New High -> one curve -> transition"
      // High compression = MORE tiny recursions required. Low = fewer large ones.
      int recRequired = compIdx>=80 ? 5 : compIdx>=55 ? 4 : compIdx>=30 ? 3 : 1;
      double recDom=fmin2(100.0,fmax2(recBrk*(30.0-compIdx*0.15),retrFrac*80.0));
      // Transition completes when: recursion count met + dominance transferred + energy exhausted
      bool energyExhausted = momExhaust || (eff<effT*0.6 && MathAbs(vel[j])<MathAbs(velP)*0.5);
      bool transferDone = recDom>=50.0 && (recBrk>=recRequired) && (energyExhausted || recDom>=75.0);
      //--- v60 RECURSIVE TRANSITION state machine (not a single latch) ---
      if(reset) phaseState=0;
      if(dir!=0 && !reset){
         if(phaseState==0 && expanding) phaseState=1;
         if(phaseState==1 && !atExtreme && momDecaying && physConvexDevel) phaseState=2;
         if(phaseState==2 && !atExtreme && momCounter && physTransfer) phaseState=3;
         if(phaseState==3 && !atExtreme && (bos1||bos2||indBrk) && physTransfer) phaseState=4;
         if(phaseState>=1 && phaseState<=7 && atExtreme && extended) phaseState=5;
         // ENTER transition on first CHoCH (but DON'T exit until recRequired met)
         if(phaseState==5 && !atExtreme && (recBrk>=1||momExhaust)) phaseState=7;
         // EXIT transition ONLY when compression-required recursions complete + transfer done
         if(phaseState==7 && transferDone) phaseState=8;
         if(phaseState==8 && atFlip) phaseState=9;
         if(phaseState==9 && ((dir==1&&bullImp)||(dir==-1&&bearImp))) phaseState=10;
         if(phaseState==10 && (oppBOS||physCapacityLow)) phaseState=11;
         if(phaseState==11 && ((dir==1&&lo<fbv)||(dir==-1&&hi>ftv))) phaseState=12;
         if(phaseState==12 && ((dir==1&&bullCH)||(dir==-1&&bearCH))) phaseState=13;
      }
      //--- map v60 code -> Letra canonical code so Letra's combiner is unchanged ---
      //  v60: 7 Transition Environment (was "Absorption" -- SPEC: not a phase but a recursive
      //  environment containing internal CHOCHs, compression, failure swings, dominance transfer),
      //  9 HTF Flip->Retr Pre-Cvx, 10 Induction->Retr Induction,
      //       11 Liquidation/12 Terminal->Retr Liquidity, 13/14 Return->Demand/Supply Return.
      int v60c=phaseState;
      if(v60c==5 && dir==-1) v60c=6;
      if(v60c==13 && dir==-1) v60c=14;
      int phase = (v60c>=1&&v60c<=6)?v60c : v60c==7?7 : v60c==8?8 : v60c==9?9 : v60c==10?10 : (v60c==11||v60c==12)?11 : v60c==13?12 : v60c==14?13 : 0;
      double wp = phaseState==0?5.0:phaseState==1?15.0:phaseState==2?25.0:phaseState==3?33.0:phaseState==4?42.0:phaseState==5?55.0:phaseState==7?65.0:phaseState==8?75.0:phaseState==9?85.0:phaseState==10?90.0:phaseState==11?94.0:phaseState==12?97.0:100.0;
      double cm = fmin2(convScore,100.0);
      double mf = fmin2(fmax2(expScore,fmax2(absScore,convScore))*0.70 + (dir!=0?30.0:0.0),100.0);
      double frzS=fmin2((eLong||eShort?50.0:0.0)+expScore*0.30+convScore*0.20,100.0);
      int dirLabel = !naf(inv)?(cl>inv?1:(cl<inv?-1:dir)):dir;

      O.dir[j]=dirLabel; O.ph[j]=phase; O.sh[j]=curSH; O.sl[j]=curSL;
      O.psh[j]=prSH; O.psl[j]=prSL; O.bos[j]=bosOut; O.ch[j]=chOut;
      O.p4h[j]=p4h; O.p4l[j]=p4l; O.inv[j]=inv; O.tgt[j]=tgt;
      O.ft[j]=ftv; O.fb[j]=fbv; O.fs[j]=frzS; O.wp[j]=wp; O.cm[j]=cm; O.mf[j]=mf;
      O.dom[j]=recDom; O.comp[j]=compIdx; O.rec[j]=(double)recBrk;   // dominance transfer % / compression / recursion depth
      O.recReq[j]=(double)recRequired;  // compression-derived required recursions for this bar
   }
}


//==================================================================
// TIME MAPPING -- project an HTF series onto a chart-bar time
// Returns index of the latest HTF bar with open-time <= ct.
//==================================================================
int MapIdx(const datetime &times[], const int n, const datetime ct)
{
   if(n<=0) return(-1);
   if(times[0]>ct) return(-1);
   int lo=0, hi=n-1, res=0;
   while(lo<=hi){ int mid=(lo+hi)>>1; if(times[mid]<=ct){ res=mid; lo=mid+1; } else hi=mid-1; }
   return(res);
}
double MapVal(const datetime &times[], const double &vals[], const int n, const datetime ct)
{
   int k=MapIdx(times,n,ct); return(k<0?NA:vals[k]);
}

//==================================================================
// PHYSICS ENGINE (f_phys) -- fixed M5
//==================================================================
struct PhysOut
{
   datetime t[]; int n;
   double atr[],vel[],acc[],cvx[],csm[],eff[],disp[];
   int bCS[],rCS[],bImp[],rImp[],bDec[],rDec[],bMic[],rMic[];
   int vd70[],vd50[],vd85[],vd553[]; double mom[]; int accDec[];
};

void ComputePhys(const ENUM_TIMEFRAMES tfReq, const int bars,
                 const int atrL, const int effL, const double effT,
                 const double dispT, const double convM, PhysOut &P)
{
   ENUM_TIMEFRAMES tf=SafeTF(tfReq);
   TFData d; if(!LoadTF(tf,bars,d) || d.n<effL+5){ P.n=0; return; }
   int n=d.n; P.n=n;
   double diff[]; ArrayResize(diff,n); diff[0]=0; for(int j=1;j<n;j++) diff[j]=d.c[j]-d.c[j-1];
   double vel[]; EMAarr(diff,vel,3);
   double acc[]; ArrayResize(acc,n); acc[0]=0; for(int j=1;j<n;j++) acc[j]=vel[j]-vel[j-1];
   double cvx[]; ArrayResize(cvx,n); cvx[0]=0; for(int j=1;j<n;j++) cvx[j]=acc[j]-acc[j-1];
   double csm[]; EMAarr(cvx,csm,3);
   double atr[]; ATRarr(d.h,d.l,d.c,atr,atrL);

   ArrayResize(P.t,n);
   ArrayResize(P.atr,n);ArrayResize(P.vel,n);ArrayResize(P.acc,n);ArrayResize(P.cvx,n);
   ArrayResize(P.csm,n);ArrayResize(P.eff,n);ArrayResize(P.disp,n);ArrayResize(P.mom,n);
   ArrayResize(P.bCS,n);ArrayResize(P.rCS,n);ArrayResize(P.bImp,n);ArrayResize(P.rImp,n);
   ArrayResize(P.bDec,n);ArrayResize(P.rDec,n);ArrayResize(P.bMic,n);ArrayResize(P.rMic,n);
   ArrayResize(P.vd70,n);ArrayResize(P.vd50,n);ArrayResize(P.vd85,n);ArrayResize(P.vd553,n);ArrayResize(P.accDec,n);

   for(int j=0;j<n;j++){
      double cl=d.c[j],op=d.o[j],hi=d.h[j],lo=d.l[j],A=atr[j];
      double velP=(j>0)?vel[j-1]:0, accP=(j>0)?acc[j-1]:0;
      double csmP=(j>0)?csm[j-1]:0, vel3=(j>2)?vel[j-3]:0;
      double mv=(j>=effL)?MathAbs(cl-d.c[j-effL]):0.0;
      double ps=SumAbsDiff(d.c,j,effL);
      double eff=(ps>0)?mv/ps:0.0;
      double disp=(hi-lo)/fmax2(A,1e-10);
      double cth=A*convM;
      P.t[j]=d.t[j]; P.atr[j]=A; P.vel[j]=vel[j]; P.acc[j]=acc[j]; P.cvx[j]=cvx[j];
      P.csm[j]=csm[j]; P.eff[j]=eff; P.disp[j]=disp; P.mom[j]=vel[j]-velP;
      P.bCS[j]=(csm[j]>cth && csmP<=cth)?1:0;
      P.rCS[j]=(csm[j]<-cth && csmP>=-cth)?1:0;
      P.bImp[j]=(eff>effT && vel[j]>velP && acc[j]>0 && cl>op && disp>dispT)?1:0;
      P.rImp[j]=(eff>effT && vel[j]<velP && acc[j]<0 && cl<op && disp>dispT)?1:0;
      P.bDec[j]=(MathAbs(acc[j])<MathAbs(accP)*0.8 && vel[j]>0)?1:0;
      P.rDec[j]=(MathAbs(acc[j])<MathAbs(accP)*0.8 && vel[j]<0)?1:0;
      P.bMic[j]=(eff>effT*0.80 && vel[j]>velP && acc[j]>0 && cl>op && disp>dispT*0.50)?1:0;
      P.rMic[j]=(eff>effT*0.80 && vel[j]<velP && acc[j]<0 && cl<op && disp>dispT*0.50)?1:0;
      P.vd70[j]=(MathAbs(vel[j])<MathAbs(velP)*0.7)?1:0;
      P.vd50[j]=(MathAbs(vel[j])<MathAbs(velP)*0.5)?1:0;
      P.vd85[j]=(MathAbs(vel[j])<MathAbs(velP)*0.85)?1:0;
      P.vd553[j]=(MathAbs(vel[j])<MathAbs(vel3)*0.55)?1:0;
      P.accDec[j]=(MathAbs(acc[j])<MathAbs(accP))?1:0;
   }
}

//==================================================================
// HTF BELIEF ENGINE (f_htfBeliefs)
//==================================================================
struct BeliefOut { datetime t[]; int n; int dir[]; double exp[],dec[],curv[],ab[],liq[]; };

void ComputeBelief(const ENUM_TIMEFRAMES tfReq, const int bars, const int atrL,
                   const double effT, const double dispT, const double convM,
                   const int obLook, BeliefOut &B)
{
   ENUM_TIMEFRAMES tf=SafeTF(tfReq);
   TFData d; if(!LoadTF(tf,bars,d) || d.n<obLook+5){ B.n=0; return; }
   int n=d.n; B.n=n;
   double diff[]; ArrayResize(diff,n); diff[0]=0; for(int j=1;j<n;j++) diff[j]=d.c[j]-d.c[j-1];
   double vel[]; EMAarr(diff,vel,3);
   double acc[]; ArrayResize(acc,n); acc[0]=0; for(int j=1;j<n;j++) acc[j]=vel[j]-vel[j-1];
   double cnv[]; ArrayResize(cnv,n); cnv[0]=0; for(int j=1;j<n;j++) cnv[j]=acc[j]-acc[j-1];
   double csm[]; EMAarr(cnv,csm,3);
   double atr[]; ATRarr(d.h,d.l,d.c,atr,atrL);
   ArrayResize(B.t,n);ArrayResize(B.dir,n);ArrayResize(B.exp,n);ArrayResize(B.dec,n);
   ArrayResize(B.curv,n);ArrayResize(B.ab,n);ArrayResize(B.liq,n);
   for(int j=0;j<n;j++){
      double cl=d.c[j],op=d.o[j],hi=d.h[j],lo=d.l[j],A=atr[j];
      double velP=(j>0)?vel[j-1]:0, accP=(j>0)?acc[j-1]:0;
      double convTh=A*convM;
      double move=(j>=obLook)?MathAbs(cl-d.c[j-obLook]):0.0;
      double pathSum=SumAbsDiff(d.c,j,obLook);
      double eff=(pathSum>0)?move/pathSum:0.0;
      double disp=(hi-lo)/fmax2(A,1e-10);
      double expScore=fmin2(eff/fmax2(effT,1e-10)*50.0+disp/fmax2(dispT,1e-10)*50.0,100.0);
      double decayScr=(MathAbs(acc[j])<MathAbs(accP)*0.8)?fmin2(MathAbs(cnv[j])/fmax2(convTh,1e-10)*50.0,100.0):0.0;
      double curvScr=fmin2(MathAbs(csm[j])/fmax2(convTh,1e-10)*50.0,100.0);
      double abScr=(eff<effT*0.7 && MathAbs(vel[j])<MathAbs(velP)*0.6)?60.0+curvScr*0.4:curvScr*0.3;
      double liqScr=(MathAbs(csm[j])>convTh*1.5 && disp>dispT)?fmin2(curvScr*1.2,100.0):curvScr*0.5;
      bool bullImp=eff>effT && vel[j]>velP && acc[j]>0 && cl>op && disp>dispT;
      bool bearImp=eff>effT && vel[j]<velP && acc[j]<0 && cl<op && disp>dispT;
      B.t[j]=d.t[j]; B.dir[j]=bullImp?1:(bearImp?-1:0);
      B.exp[j]=expScore; B.dec[j]=decayScr; B.curv[j]=curvScr; B.ab[j]=abScr; B.liq[j]=liqScr;
   }
}

//==================================================================
// M1 PHYSICS ENGINE (f_m1Physics) -- fixed "1"
//==================================================================
struct M1Out { datetime t[]; int n; int expWeak[],convEmer[],indEmer[],liqEmer[],absEmer[]; };

void ComputeM1(const int bars, const int atrL, const int effL, const double effT,
               const double dispT, const double convM, M1Out &M)
{
   ENUM_TIMEFRAMES tf=SafeTF(PERIOD_M1);
   TFData d; if(!LoadTF(tf,bars,d) || d.n<effL+5){ M.n=0; return; }
   int n=d.n; M.n=n;
   double diff[]; ArrayResize(diff,n); diff[0]=0; for(int j=1;j<n;j++) diff[j]=d.c[j]-d.c[j-1];
   double v[]; EMAarr(diff,v,3);
   double a[]; ArrayResize(a,n); a[0]=0; for(int j=1;j<n;j++) a[j]=v[j]-v[j-1];
   double cv[]; ArrayResize(cv,n); cv[0]=0; for(int j=1;j<n;j++) cv[j]=a[j]-a[j-1];
   double atr[]; ATRarr(d.h,d.l,d.c,atr,atrL);
   ArrayResize(M.t,n);ArrayResize(M.expWeak,n);ArrayResize(M.convEmer,n);
   ArrayResize(M.indEmer,n);ArrayResize(M.liqEmer,n);ArrayResize(M.absEmer,n);
   for(int j=0;j<n;j++){
      double cl=d.c[j],hi=d.h[j],lo=d.l[j],A=atr[j];
      double aP=(j>0)?a[j-1]:0;
      double m=(j>=effL)?MathAbs(cl-d.c[j-effL]):0.0;
      double ps=SumAbsDiff(d.c,j,effL);
      double e=(ps>0)?m/ps:0.0;
      double dd=(hi-lo)/fmax2(A,1e-10);
      bool mD=MathAbs(a[j])<MathAbs(aP)*0.8;
      M.t[j]=d.t[j];
      M.expWeak[j]=(e<effT*0.7 && mD)?1:0;
      M.convEmer[j]=(MathAbs(cv[j])>A*convM*1.5 && mD)?1:0;
      M.indEmer[j]=(e>effT && a[j]<0 && v[j]>0)?1:0;
      M.liqEmer[j]=(dd>dispT*1.2 && mD)?1:0;
      M.absEmer[j]=(e<effT*0.5 && dd<dispT*0.6)?1:0;
   }
}

//==================================================================
// FU POOL ENGINE (f_fuPool) -- multi-TF recursive FU left-pool magnets
//==================================================================
struct FUPoolOut { datetime t[]; int n; double pool[],mid[],bandHi[],bandLo[],tip[],score[]; int dir[],valid[]; };

void ComputeFUPool(const ENUM_TIMEFRAMES tfReq, const int bars, const double wickFrac, FUPoolOut &F)
{
   ENUM_TIMEFRAMES tf=SafeTF(tfReq);
   TFData d; if(!LoadTF(tf,bars,d) || d.n<6){ F.n=0; return; }
   int n=d.n; F.n=n;
   double atr14[]; ATRarr(d.h,d.l,d.c,atr14,14);
   ArrayResize(F.t,n);ArrayResize(F.pool,n);ArrayResize(F.mid,n);ArrayResize(F.bandHi,n);
   ArrayResize(F.bandLo,n);ArrayResize(F.tip,n);ArrayResize(F.score,n);ArrayResize(F.dir,n);ArrayResize(F.valid,n);
   //--- state ---
   double tip=NA,bH=NA,bL=NA,pool=NA; int dir=0; bool valid=false,conf=false;
   for(int j=0;j<n;j++){
      double cl=d.c[j],op=d.o[j],hi=d.h[j],lo=d.l[j];
      double rng=fmax2(hi-lo,1e-10);
      double priorHi=HighestPrior(d.h,j,3);
      double priorLo=LowestPrior(d.l,j,3);
      bool bear=!naf(priorHi) && hi>priorHi && cl<priorHi && (hi-fmax2(op,cl))/rng>=wickFrac;
      bool bull=!naf(priorLo) && lo<priorLo && cl>priorLo && (fmin2(op,cl)-lo)/rng>=wickFrac;
      if(bear){ dir=-1; tip=hi; bH=fmax2(op,cl); bL=fmin2(op,cl); pool=priorHi; valid=true; conf=false; }
      else if(bull){ dir=1; tip=lo; bH=fmax2(op,cl); bL=fmin2(op,cl); pool=priorLo; valid=true; conf=false; }
      if(valid && dir==-1 && !conf && cl<bL) conf=true;
      if(valid && dir==1  && !conf && cl>bH) conf=true;
      double mid=NA,bHi=NA,bLo=NA;
      if(dir==-1 && !naf(tip)){ mid=bH+(tip-bH)*0.50; bHi=bH+(tip-bH)*0.62; bLo=bH+(tip-bH)*0.38; }
      else if(dir==1 && !naf(tip)){ mid=tip+(bL-tip)*0.50; bHi=tip+(bL-tip)*0.62; bLo=tip+(bL-tip)*0.38; }
      double wkAtr=(dir==-1 && !naf(tip))?(tip-bH)/fmax2(atr14[j],1e-10):((dir==1 && !naf(tip))?(bL-tip)/fmax2(atr14[j],1e-10):0.0);
      double score=(conf?30.0:0.0)+fmin2(25.0,wkAtr*15.0)+20.0+(wkAtr>1.0?15.0:0.0)+(wkAtr>1.5?10.0:0.0);
      F.t[j]=d.t[j];
      F.pool[j]=valid?pool:NA; F.mid[j]=mid; F.bandHi[j]=bHi; F.bandLo[j]=bLo;
      F.dir[j]=dir; F.valid[j]=valid?1:0; F.tip[j]=tip; F.score[j]=score;
   }
}

//==================================================================
// HTF DIR (f_htfDir) -- V72 MCE single-direction read
//==================================================================
struct DirOut { datetime t[]; int n; int dir[]; };

void ComputeHtfDir(const ENUM_TIMEFRAMES tfReq, const int bars, const int atrL,
                   const double effT, const double dispT, const int obLook, DirOut &R)
{
   ENUM_TIMEFRAMES tf=SafeTF(tfReq);
   TFData d; if(!LoadTF(tf,bars,d) || d.n<obLook+5){ R.n=0; return; }
   int n=d.n; R.n=n;
   double diff[]; ArrayResize(diff,n); diff[0]=0; for(int j=1;j<n;j++) diff[j]=d.c[j]-d.c[j-1];
   double vel[]; EMAarr(diff,vel,3);
   double acc[]; ArrayResize(acc,n); acc[0]=0; for(int j=1;j<n;j++) acc[j]=vel[j]-vel[j-1];
   double atr[]; ATRarr(d.h,d.l,d.c,atr,atrL);
   ArrayResize(R.t,n);ArrayResize(R.dir,n);
   for(int j=0;j<n;j++){
      double cl=d.c[j],op=d.o[j],hi=d.h[j],lo=d.l[j],A=atr[j];
      double velP=(j>0)?vel[j-1]:0;
      double move=(j>=obLook)?MathAbs(cl-d.c[j-obLook]):0.0;
      double pathSum=SumAbsDiff(d.c,j,obLook);
      double eff=(pathSum>0)?move/pathSum:0.0;
      double disp=(hi-lo)/fmax2(A,1e-10);
      bool bullImp=eff>effT && vel[j]>velP && acc[j]>0 && cl>op && disp>dispT;
      bool bearImp=eff>effT && vel[j]<velP && acc[j]<0 && cl<op && disp>dispT;
      R.t[j]=d.t[j]; R.dir[j]=bullImp?1:(bearImp?-1:0);
   }
}


//==================================================================
// PHASE-STRING HELPERS (shared canonical vocabulary)
//==================================================================
string f_phaseStr(const int c)
{
   switch(c){
      case 1:  return("Expansion");
      case 2:  return("Expansion Pre-Convexity");
      case 3:  return("Expansion Induction");
      case 4:  return("Expansion Liquidity");
      case 5:  return("New High");
      case 6:  return("New Low");
      case 7:  return("Transition Environment");
      case 8:  return("Retracement");
      case 9:  return("Retracement Pre-Convexity");
      case 10: return("Retracement Induction");
      case 11: return("Retracement Liquidity");
      case 12: return("Demand Return");
      case 13: return("Supply Return");
   }
   return("Point 4 Origin");
}
string f_hypFam(const string ph)
{
   if(ph=="Expansion")                 return("EXPANSION");
   if(ph=="Expansion Pre-Convexity")   return("CONVEXITY FORMING");
   if(ph=="Expansion Induction")       return("CONVEXITY FORMING");
   if(ph=="Expansion Liquidity")       return("CONVEXITY FORMING");
   if(ph=="New High")                  return("CREATION FORMING");
   if(ph=="New Low")                   return("CREATION FORMING");
   if(ph=="Transition Environment")    return("TRANSITION ENVIRONMENT");
   if(ph=="Demand Return")             return("DEMAND/SUPPLY RETURN");
   if(ph=="Supply Return")             return("DEMAND/SUPPLY RETURN");
   return("RETRACEMENT");
}
string f_famSimple(const int f)
{
   if(f==1) return("Expansion");
   if(f==2) return("Pre-Convexity");
   if(f==4) return("Transition Environment");
   if(f==5) return("Liquidity");
   if(f==6) return("Transition Environment");
   return("Expansion");
}
string f_famMicro(const int f)
{
   if(f==2) return("M1 Convexity");
   if(f==4) return("M1 Transition Environment");
   if(f==5) return("M1 Liquidity");
   return("M1 Expansion");
}
int f_phaseFamilyCode(const int c)
{
   if(c==1) return(1);
   if(c==2 || c==3 || c==4) return(2);
   if(c==5 || c==6) return(3);
   if(c==7) return(4);
   if(c==8 || c==9 || c==10 || c==11) return(5);
   if(c==12 || c==13) return(6);
   return(0);
}
string f_waveDirLabel(const int d){ return(d==1?"Bullish Wave":(d==-1?"Bearish Wave":"Neutral")); }
int f_waveDirByOrigin(const double origin,const double cl,const int fb)
{ return(!naf(origin)?(cl>origin?1:(cl<origin?-1:fb)):fb); }

//==================================================================
// GLOBAL ENGINE INSTANCES (recomputed on each new chart bar)
//==================================================================
SEOut     se1,se3,se5,se15,se60,se240;
PhysOut   phys5;
BeliefOut bel1,bel2;
M1Out     m1o;
FUPoolOut fpW,fpD,fpH4,fpH1,fpM15,fpM5;
DirOut    mdir3,mdir4;

int HTF_BARS = 4000;   // bars to pull per HTF engine (set in OnInit)

//==================================================================
// PER-BAR SIGNAL OUTPUTS (consumed by indicator buffers / EA logic)
//==================================================================
bool   gBarLong=false; bool gBarShort=false; double gBarLongPx=0; double gBarShortPx=0;

//==================================================================
// PERSISTENT CHART-LEVEL STATE  (Pine 'var')
//==================================================================
//--- Sec4 structure ---
double g_lastPivHigh=NA,g_prevPivHigh=NA,g_lastPivLow=NA,g_prevPivLow=NA;
int    g_structBias=0;
double g_prevSwingHigh=NA,g_prevSwingLow=NA,g_currSwingHigh=NA,g_currSwingLow=NA;
//--- Sec5 pivot memory ---
double g_lastPivotPrice=NA,g_prevPivotPrice=NA;
int    g_lastPivotBar=-1,g_prevPivotBar=-1,g_lastPivotDir=0,g_prevPivotDir=0;
//--- Sec8 wave context ---
int    g_direction=0; double g_flipTop=NA,g_flipBot=NA;
int    g_obBirthBar=-1,g_barsInZone=0,g_contBar=-1;
double g_point4OriginHigh=NA,g_point4OriginLow=NA; int g_point4OriginBar=-1;
double g_flipzoneInducPrice=NA,g_flipzoneInducLow=NA,g_flipzoneInducHigh=NA;
double g_inducExpOriginHigh=NA,g_inducExpExtremeLow=NA,g_inducExpOriginLow=NA,g_inducExpExtremeHigh=NA;
double g_inducRetrOriginHigh=NA,g_inducRetrExtremeLow=NA,g_inducRetrOriginLow=NA,g_inducRetrExtremeHigh=NA;
double g_inducZoneLow=NA,g_inducZoneHigh=NA,g_cycleHigh=NA,g_cycleLow=NA;
int    g_waveGeneration=0,g_entryCycle=0; bool g_isRecursiveWave=false; int g_waveDepth=0,g_lastSpawnDir=0; bool g_recursiveComplete=false;
//--- cycle history store ---
double g_cycObTop[4],g_cycObBot[4],g_cycFlipTop[4],g_cycFlipBot[4],g_cycP4High[4],g_cycP4Low[4];
int    g_cycStartBar[4],g_cycDir[4];
//--- Sec9/12 forward-declared smoothed states ---
double g_liqHeat=0.0; bool g_nearFlipzone=false; double g_convexityMaturity=0.0;
double g_waveProgress=30.0,g_waveModelFit=50.0;
double g_expansionBelief=0,g_convexityBelief=0,g_creationBelief=0,g_absorptionBelief=0,g_retracementBelief=0,g_demandReturnBelief=0;
double g_modelConfidence=50.0;
bool   g_inductionEvidence=false,g_preConvEvidence=false,g_closeInside=false;
bool   g_m1AbsorptionEmer=false,g_m1ConvexityEmer=false,g_m1LiquidityEmer=false;
//--- validation ring ---
int    g_predOutcomes[100]; int g_predTotalIdx=0;
string g_lastExpectedPhase="Point 4 Origin",g_lastIE1APhase="Point 4 Origin";
//--- liqg overlay ---
bool   g_liqg_active=false,g_liqg_isRetr=false; int g_liqg_dir=0;
double g_liqg_target=NA,g_liqg_initDist=NA; bool g_liqg_absorbUnlocked=false;
//--- recursive ---
bool   g_recursiveJustFired=false; int g_recursiveFiredBar=-1;
//--- liquidity heatmap arrays ---
double g_liqLevels[],g_liqWeights[]; int g_liqAges[],g_liqTypes[];
//--- exec lock ---
int    g_lastSignalBar=-1,g_lastLongBar=-1,g_lastShortBar=-1; bool g_engineArmed=true;
//--- trade state ---
int    g_tradeDir=0,g_exitFiredBar=-1;
//--- CONTINUATION HUNT MODE (Layer 2: demand/supply expansion entries after flip zone trade) ---
int    g_huntMode=0;          // 0=off, 1=hunting longs at demand, -1=hunting shorts at supply
int    g_huntActivatedBar=-1; // bar when hunt mode activated
double g_huntDemandHi=NA;     // upper boundary of the demand hunt zone
double g_huntDemandLo=NA;     // lower boundary of the demand hunt zone
//--- previous-bar series memory ---
double g_prevEnergy=0.0; int g_prevDirection=0,g_prevEntryCycle=0,g_prev_ede_state=0; bool g_prev_LBD=false;
//--- FU blocks ---
double g_fu_top[],g_fu_bot[]; int g_fu_birthBar[],g_fu_dir[]; string g_fu_state[];
//--- FU wick authority ---
double g_fuw_tip=NA,g_fuw_bodyHigh=NA,g_fuw_bodyLow=NA,g_fuw_mid=NA,g_fuw_mid38=NA,g_fuw_mid62=NA;
int    g_fuw_dir=0; double g_fuw_leftPool=NA; int g_fuw_bar=-1; bool g_fuw_valid=false; double g_fuw_strength=NA;
//--- AFE ---
int    g_afe_step=0; double g_afe_origin=NA; int g_afe_originDir=0;
double g_afe_upperFlip=NA,g_afe_lowerFlip=NA; string g_afe_upperFlipRole="-";
double g_afe_activeDest=NA,g_afe_target=NA; bool g_afe_selfReturnDone=false,g_afe_continuation=false;
//--- FRZ arrays ---
double g_frz_top[],g_frz_bot[]; int g_frz_bar[],g_frz_dir[],g_frz_score[];
string g_frz_class[],g_frz_tier[],g_frz_tierF[],g_frz_comp[],g_frz_owner[],g_frz_status[];
int    g_frz_idx[]; int g_frz_totalSpawned=0;
//--- DIE clustering / density ---
int    g_die_clusterCount=0,g_die_clusterStartBar=-1; double g_die_clusterBestScore=0; bool g_die_inCluster=false;
bool   g_die_objMade=false,g_die_absUnlocked=false;
//--- dashboard EMA confidences ---
double g_l1_confidence=50.0,g_l2_confidence=50.0;
//--- wave / delivery registries (V72) ---
int    g_wr_id[],g_wr_parent[],g_wr_root[],g_wr_birth[],g_wr_death[],g_wr_depth[];
string g_wr_spawnPh[],g_wr_deathPh[]; double g_wr_peak[],g_wr_resScore[];
int    g_wr_nextId=1,g_wr_activeId=0,g_wr_activeParent=0,g_wr_activeRoot=0;
int    g_dwr_id[],g_dwr_root[],g_dwr_start[],g_dwr_end[],g_dwr_cycle[]; double g_dwr_energy[]; string g_dwr_res[];
int    g_dwr_nextId=1,g_dwr_activeId=0;

//--- last fully-processed chart bar index (for incremental state) ---
int    g_lastProcessed=-1;
datetime g_lastHTFbuild=0;


//==================================================================
// DISPLAY STATE (written every processed bar; last bar drives render)
//==================================================================
//--- phase / direction ---
string cur_ie1aPhase, cur_currentDisplayPhase, cur_hypFamily;
int    cur_dirM1,cur_dirM3,cur_dirM5,cur_dirM15,cur_dirH1,cur_dirH4;
//--- multi-timeframe entry: a fresh Demand/Supply Return on ANY rung (M1..H4) ---
int    cur_mtfEntryDir=0;      // +1 long / -1 short / 0 none
bool   cur_mtfEntryFresh=false;// the Return just formed on this bar (transition)
int    cur_mtfEntryWt=0;       // rung weight (1=M1 ... 6=H4)
double cur_mtfEntryInv=NA;     // that rung's invalidation level (for the stop)
string cur_mtfEntryTF="-";     // which timeframe presented it
double cur_mtfEntryDom=0.0;    // dominance-transfer % of the entry rung (first-strike vs entry-cycle)
//--- CURVE OWNERSHIP CONTEXT (F72): the map the EA builds before any entry ---
string cur_curveOwner="-";     // rung that owns price (highest mid-progress curve)
int    cur_ownerDir=0;         // owner curve direction
string cur_transState="-";     // BUILDING / TRANSITION / COMPLETE / APPROACHING FLIP / TERMINAL / ENTRY
string cur_compRegime="-";     // Low / Medium / High / Extreme (compression near terminal)
int    cur_recDepth=0;         // recursion count on the owner curve
int    cur_ownerDeathSignals=0; // 0-4: how many death signals agree (unified ownership death)
double cur_domTransfer=0.0;    // owner curve dominance transfer %
string cur_entryReady="Not Ready"; // Not Ready / Early / Building / Pre-entry / Entry Active / Terminal
//--- CURVE CAPACITY (F72): how much curve is left -> how many recursions are possible ---
double cur_curveBudget=0.0;    // 0..100 remaining curve capacity to the HTF flip/objective
int    cur_expRecDepth=0;      // expected recursive cycles still possible (0..4)
double cur_transMaturity=0.0;  // transition maturity % (= dominance transfer)
double cur_entryProb=0.0;      // entry-cycle probability %
double cur_distFlipAtr=0.0;    // distance to HTF flip/objective in ATR
//--- MULTI-CURVE FLIP CONTEXT (stored for EA TryEnter access) ---
double cur_ctxFlipTop=NA, cur_ctxFlipBot=NA, cur_ctxFlipMid=NA;
//--- PER-TIMEFRAME CURVE CONTEXT (ported from V60 -- origin->extreme->flip per curve) ---
// Each curve on each TF has: origin (seN_inv), extreme (swing hi/lo), flip zone (seN_ft/fb)
// Parallel arrays: [0]=M1, [1]=M3, [2]=M5, [3]=M15, [4]=H1, [5]=H4
int    cur_cv_dir[6];
double cur_cv_origin[6];
double cur_cv_extreme[6];
double cur_cv_flipTop[6];
double cur_cv_flipBot[6];
double cur_cv_flipMid[6];
double cur_cv_wp[6];
double cur_cv_dom[6];
double cur_cv_comp[6];
int    cur_cv_phase[6];
//--- prev-bar phase code per rung (persist across recomputes; NOT reset by ResetState) ---
int    gPrevPhM1=-1,gPrevPhM3=-1,gPrevPhM5=-1,gPrevPhM15=-1,gPrevPhH1=-1,gPrevPhH4=-1;
string cur_l0phase,cur_l1phase,cur_l2phase,cur_l3phase,cur_l4phase;
double cur_phaseConfidence,cur_phaseIntegrity,cur_phaseProgress,cur_ie1aPhaseConf;
double cur_fractalStackScore,cur_fractalCtxScore; int cur_fractalStackDir;
int    cur_liveWaveDir,cur_liveHtfAlign;
//--- liqg ---
bool   cur_liqgActive; string cur_liqgTitle,cur_liqgSub,cur_liqgReadout,cur_liqgArr;
double cur_liqgTarget,cur_liqgDistPct;
//--- physics ---
double cur_atr,cur_velocity,cur_acceleration,cur_efficiency,cur_displacement;
double cur_convSmooth,cur_velocityScore,cur_accelScore,cur_convexityScore,cur_expansionScore;
double cur_obsExp,cur_obsDecay,cur_obsCurv,cur_obsAbs,cur_obsLiq,cur_physicsConsensus,cur_physicsMax,cur_physicsDiff;
string cur_volRegime; double cur_volRatio;
//--- beliefs / proximity / hyp / pred ---
double cur_bExp,cur_bConv,cur_bCreat,cur_bAbs,cur_bRetr,cur_bDR;
double cur_pxExp,cur_pxConv,cur_pxCreat,cur_pxAbs,cur_pxRetr,cur_pxDR;
string cur_primaryHyp; double cur_primaryHypConf;
double cur_hypLE,cur_hypEC,cur_hypCF,cur_hypAA,cur_hypRA,cur_hypDR2;
string cur_expectedNextPhase; double cur_expectedNextProb,cur_predReliability,cur_predAcc10,cur_predAcc25;
double cur_modelConfidence,cur_waveDeviation; bool cur_deviationAlert;
int    cur_m1WarningScore; string cur_m1Warning;
double cur_htfExpBelief,cur_htfConvBelief,cur_htfAbsBelief,cur_htfLiqBelief;
//--- market state / scoring ---
double cur_contProb,cur_finalProb; string cur_grade; color cur_gradeCol;
int    cur_structBias,cur_htfAlign,cur_resonance;
//--- liquidity ---
double cur_liqHeat; string cur_liqZone; bool cur_liqVacuum;
//--- geometry ---
string cur_cycleCapacity,cur_geoCapNarr; double cur_geoCapScore,cur_availableSpace,cur_zonePrecision;
//--- ERF ---
int    cur_edeState; string cur_edeCleaning; double cur_edeDissProg,cur_edeExpEnergy;
string cur_reResolution; double cur_reRecursiveCompletion,cur_reResidual,cur_reRevisit;
string cur_eaeEnergyState,cur_eaePrimaryLabel; double cur_eaePrimaryPrice,cur_eaePrimaryScore,cur_eaeSecondaryPrice;
double cur_erfTradeReadiness,cur_erfConfidence; bool cur_erfEntryGate,cur_erfSuppressRotation;
//--- probability panels ---
double cur_expansionProbability,cur_reversalProbability,cur_tradeReadiness;
//--- directive / edge ---
string cur_directiveStr; color cur_directiveCol; string cur_liveDirective;
double cur_buyProb,cur_sellProb,cur_netEdgeAdjusted,cur_buyScore,cur_sellScore;
//--- live opp / exec ---
double cur_dieEntryScore; string cur_dieFuContrib; bool cur_longSignal,cur_shortSignal; int cur_tradeDir;
//--- cycles ---
int    cur_entryCycle,cur_waveDepth; bool cur_recursiveComplete;
double cur_cyc1,cur_cyc2,cur_cyc3,cur_cyc4; string cur_activeCyclePhase;
//--- dominance / fusion ---
string cur_l0domPhase,cur_l1domPhase,cur_l2domPhase,cur_l3domPhase;
double cur_l0conf,cur_l1conf,cur_l2conf,cur_l3conf;
double cur_l0dom,cur_l1dom,cur_l2dom,cur_l3dom;
string cur_dominantWaveLevel,cur_fusionInterp; double cur_fusionConfidence;
string cur_parentChildRel,cur_childGrandRel;
//--- FRZ display ---
int    cur_frzActive,cur_frzBull,cur_frzBear,cur_frzBest,cur_frzL0,cur_frzL1,cur_frzL2,cur_frzL3;
string cur_frzBestClass,cur_frzBestTier,cur_frzBestComp,cur_frzBestOwner,cur_frzBestStatus;
double cur_frzBestTop,cur_frzBestBot,cur_frzBestMid; int cur_frzBestDir;
//--- FU display ---
bool   cur_anyBullFU,cur_anyBearFU; double cur_fuWinTarget,cur_fuWinBand,cur_fuRecursiveAlign; string cur_fuWinSrc;
double cur_convSeekPx,cur_convSeekSc,cur_convConfidence; string cur_convSeekTf;
//--- V72 ---
string cur_rotState; double cur_rotTransfer,cur_rotControl;
double cur_mceAlign,cur_mceHtfAlign,cur_mceExecAlign; string cur_mceHtfSummary,cur_mceExecSummary; int cur_mceLifecycle;
string cur_neNarrative; double cur_neStrength;
double cur_invActiveStop,cur_invRisk; bool cur_invInvalidated;
double cur_teTp1,cur_teTp2,cur_teTp3,cur_teRR; string cur_teExpectedPath;
string cur_tqeGrade,cur_tqeRisk; double cur_tqeRaw;
string cur_doeBias,cur_doeAction,cur_doeTradeType,cur_doeTrigger; double cur_doeConfidence,cur_doeEntryMid,cur_doeEntryHigh,cur_doeEntryLow;
double cur_oppProgress; string cur_oppState,cur_cmdNarrative;
double cur_tplMainTarget,cur_tplConfidence; string cur_tplSource,cur_tplWinnerClass;
string cur_trcDecision,cur_trcConf,cur_trcWaveChain;
//--- chart-bar rolling helpers ---
double g_atrChart[]; double g_volChart[]; double g_velHist[];


//==================================================================
// FORMAT + CHART-PIVOT HELPERS
//==================================================================
string PXs(const double v){ return(naf(v)?"-":DoubleToString(v,_Digits)); }
string PCTs(const double v){ return(naf(v)?"-":IntegerToString((int)MathRound(v))+"%"); }
string R0(const double v){ return(IntegerToString((int)MathRound(v))); }
int MapValI(const datetime &times[], const int &vals[], const int n, const datetime ct){ int k=MapIdx(times,n,ct); return(k<0?0:vals[k]); }

double ChartPivotHigh(const double &h[], const int i, const int len)
{
   int ctr=i-len; if(ctr-len<0) return(NA);
   double v=h[ctr];
   for(int k=ctr-len;k<=ctr+len;k++){ if(k==ctr) continue; if(h[k]>=v) return(NA); }
   return(v);
}
double ChartPivotLow(const double &l[], const int i, const int len)
{
   int ctr=i-len; if(ctr-len<0) return(NA);
   double v=l[ctr];
   for(int k=ctr-len;k<=ctr+len;k++){ if(k==ctr) continue; if(l[k]<=v) return(NA); }
   return(v);
}
double SMAlastN(const double &arr[], const int n)
{
   int sz=ArraySize(arr); if(sz==0) return(0); int cnt=(sz<n)?sz:n; double s=0;
   for(int k=sz-cnt;k<sz;k++) s+=arr[k]; return(s/cnt);
}

//--- htf bias persistent (Sec3) ---
int g_htfBias1=0,g_htfBias2=0;

//==================================================================
// PROCESS A SINGLE CHART BAR -- full faithful pipeline
//==================================================================
void ProcessBar(const int i,const double &o[],const double &h[],const double &l[],
                const double &c[],const datetime &tm[],const double &vol[],
                const int total,const bool isLast)
{
   datetime ct=tm[i];
   double cl=c[i], op=o[i], hi=h[i], lo=l[i];

   //==============================================================
   // MAP HTF STRUCTURE ENGINES (lookahead-off -> last closed bar)
   //==============================================================
   double se1_ph =MapVal(se1.t,se1.ph,se1.n,ct),   se1_inv=MapVal(se1.t,se1.inv,se1.n,ct),   se1_dir=MapVal(se1.t,se1.dir,se1.n,ct),   se1_bos=MapVal(se1.t,se1.bos,se1.n,ct),   se1_ch=MapVal(se1.t,se1.ch,se1.n,ct);
   double se3_ph =MapVal(se3.t,se3.ph,se3.n,ct),   se3_inv=MapVal(se3.t,se3.inv,se3.n,ct),   se3_dir=MapVal(se3.t,se3.dir,se3.n,ct),   se3_bos=MapVal(se3.t,se3.bos,se3.n,ct),   se3_ch=MapVal(se3.t,se3.ch,se3.n,ct),  se3_mf=MapVal(se3.t,se3.mf,se3.n,ct),  se3_wp=MapVal(se3.t,se3.wp,se3.n,ct),  se3_cm=MapVal(se3.t,se3.cm,se3.n,ct);
   double se5_ph =MapVal(se5.t,se5.ph,se5.n,ct),   se5_inv=MapVal(se5.t,se5.inv,se5.n,ct),   se5_dir=MapVal(se5.t,se5.dir,se5.n,ct),   se5_bos=MapVal(se5.t,se5.bos,se5.n,ct),   se5_ch=MapVal(se5.t,se5.ch,se5.n,ct);
   double se5_tgt=MapVal(se5.t,se5.tgt,se5.n,ct),  se5_p4h=MapVal(se5.t,se5.p4h,se5.n,ct),   se5_p4l=MapVal(se5.t,se5.p4l,se5.n,ct),   se5_wp=MapVal(se5.t,se5.wp,se5.n,ct),     se5_cm=MapVal(se5.t,se5.cm,se5.n,ct),  se5_mf=MapVal(se5.t,se5.mf,se5.n,ct);
   double se15_ph=MapVal(se15.t,se15.ph,se15.n,ct),se15_inv=MapVal(se15.t,se15.inv,se15.n,ct),se15_dir=MapVal(se15.t,se15.dir,se15.n,ct),se15_mf=MapVal(se15.t,se15.mf,se15.n,ct),se15_wp=MapVal(se15.t,se15.wp,se15.n,ct);
   double se60_ph=MapVal(se60.t,se60.ph,se60.n,ct),se60_inv=MapVal(se60.t,se60.inv,se60.n,ct),se60_dir=MapVal(se60.t,se60.dir,se60.n,ct),se60_mf=MapVal(se60.t,se60.mf,se60.n,ct),se60_wp=MapVal(se60.t,se60.wp,se60.n,ct);
   double se240_ph=MapVal(se240.t,se240.ph,se240.n,ct),se240_inv=MapVal(se240.t,se240.inv,se240.n,ct),se240_dir=MapVal(se240.t,se240.dir,se240.n,ct);

   string m1_phaseCanon=f_phaseStr((int)nz(se1_ph));
   string l3_phaseCanon=f_phaseStr((int)nz(se3_ph));
   string l0_phaseCanon=f_phaseStr((int)nz(se5_ph));
   string l1_phaseCanon=f_phaseStr((int)nz(se15_ph));
   string l2_phaseCanon=f_phaseStr((int)nz(se60_ph));
   string l4_phaseCanon=f_phaseStr((int)nz(se240_ph));

   int m1_dir=f_waveDirByOrigin(se1_inv,cl,(int)nz(se1_dir));
   int l3_dir=f_waveDirByOrigin(se3_inv,cl,(int)nz(se3_dir));
   int l0_dir=f_waveDirByOrigin(se5_inv,cl,(int)nz(se5_dir));
   int l1_dir=f_waveDirByOrigin(se15_inv,cl,(int)nz(se15_dir));
   int l2_dir=f_waveDirByOrigin(se60_inv,cl,(int)nz(se60_dir));
   int l4_dir=f_waveDirByOrigin(se240_inv,cl,(int)nz(se240_dir));

   int stackBull=(m1_dir==1?1:0)+(l3_dir==1?1:0)+(l0_dir==1?1:0)+(l1_dir==1?1:0)+(l2_dir==1?1:0)+(l4_dir==1?1:0);
   int stackBear=(m1_dir==-1?1:0)+(l3_dir==-1?1:0)+(l0_dir==-1?1:0)+(l1_dir==-1?1:0)+(l2_dir==-1?1:0)+(l4_dir==-1?1:0);
   int fractalStackDir=stackBull>stackBear?1:(stackBear>stackBull?-1:0);
   double fractalStackScore=(double)MathMax(stackBull,stackBear)/6.0*100.0;
   int liveWaveDir=l0_dir;
   int liveHtfAlign=(l2_dir!=0 && l2_dir==l4_dir)?l2_dir:0;
   double fractalCtxScore=fmin2(
        (l4_dir==fractalStackDir&&fractalStackDir!=0?30.0:0.0)+
        (l2_dir==fractalStackDir&&fractalStackDir!=0?26.0:0.0)+
        (l1_dir==fractalStackDir&&fractalStackDir!=0?20.0:0.0)+
        (l0_dir==fractalStackDir&&fractalStackDir!=0?14.0:0.0)+
        (l3_dir==fractalStackDir&&fractalStackDir!=0?6.0:0.0)+
        (m1_dir==fractalStackDir&&fractalStackDir!=0?4.0:0.0),100.0);
   int displayWaveDir_M5=l0_dir;

   //==============================================================
   // PHYSICS (mapped M5) + chart aliases
   //==============================================================
   double atr        =nz(MapVal(phys5.t,phys5.atr,phys5.n,ct),1e-10);
   double velocity   =MapVal(phys5.t,phys5.vel,phys5.n,ct);
   double acceleration=MapVal(phys5.t,phys5.acc,phys5.n,ct);
   double convexity  =MapVal(phys5.t,phys5.cvx,phys5.n,ct);
   double convSmooth =MapVal(phys5.t,phys5.csm,phys5.n,ct);
   double efficiency =MapVal(phys5.t,phys5.eff,phys5.n,ct);
   double displacement=MapVal(phys5.t,phys5.disp,phys5.n,ct);
   bool bullConvShift=MapValI(phys5.t,phys5.bCS,phys5.n,ct)!=0;
   bool bearConvShift=MapValI(phys5.t,phys5.rCS,phys5.n,ct)!=0;
   bool bullImpulse  =MapValI(phys5.t,phys5.bImp,phys5.n,ct)!=0;
   bool bearImpulse  =MapValI(phys5.t,phys5.rImp,phys5.n,ct)!=0;
   bool bullMomDecay =MapValI(phys5.t,phys5.bDec,phys5.n,ct)!=0;
   bool bearMomDecay =MapValI(phys5.t,phys5.rDec,phys5.n,ct)!=0;
   bool bullMicroImpulse=MapValI(phys5.t,phys5.bMic,phys5.n,ct)!=0;
   bool bearMicroImpulse=MapValI(phys5.t,phys5.rMic,phys5.n,ct)!=0;
   bool phys_vd70=MapValI(phys5.t,phys5.vd70,phys5.n,ct)!=0;
   bool phys_vd50=MapValI(phys5.t,phys5.vd50,phys5.n,ct)!=0;
   double phys_mom=MapVal(phys5.t,phys5.mom,phys5.n,ct);
   double convThreshold=atr*convMult;

   //--- vol regime (SMA20 of mapped atr over chart bars) ---
   ArrayResize(g_atrChart,ArraySize(g_atrChart)+1); g_atrChart[ArraySize(g_atrChart)-1]=atr;
   double atrSma=SMAlastN(g_atrChart,20);
   double volRatio=atr/fmax2(atrSma,1e-10);
   string volRegime=volRatio>1.5?"HIGH":(volRatio<0.7?"LOW":"NORMAL");
   double volMult=fmax2(0.5,fmin2(volRatio,2.5));

   //==============================================================
   // HTF BELIEFS (tf1/tf2)  + Sec3 bias
   //==============================================================
   int dir_tf1=MapValI(bel1.t,bel1.dir,bel1.n,ct), dir_tf2=MapValI(bel2.t,bel2.dir,bel2.n,ct);
   double expScr_tf1=nz(MapVal(bel1.t,bel1.exp,bel1.n,ct)), expScr_tf2=nz(MapVal(bel2.t,bel2.exp,bel2.n,ct));
   double decScr_tf1=nz(MapVal(bel1.t,bel1.dec,bel1.n,ct)), decScr_tf2=nz(MapVal(bel2.t,bel2.dec,bel2.n,ct));
   double curvScr_tf1=nz(MapVal(bel1.t,bel1.curv,bel1.n,ct)),curvScr_tf2=nz(MapVal(bel2.t,bel2.curv,bel2.n,ct));
   double abScr_tf1=nz(MapVal(bel1.t,bel1.ab,bel1.n,ct)),    abScr_tf2=nz(MapVal(bel2.t,bel2.ab,bel2.n,ct));
   double liqScr_tf1=nz(MapVal(bel1.t,bel1.liq,bel1.n,ct)),  liqScr_tf2=nz(MapVal(bel2.t,bel2.liq,bel2.n,ct));
   if(expScr_tf1>60 && dir_tf1!=0) g_htfBias1=dir_tf1;
   if(expScr_tf2>60 && dir_tf2!=0) g_htfBias2=dir_tf2;
   if(decScr_tf1>70 && dir_tf1==g_htfBias1) g_htfBias1=0;
   if(decScr_tf2>70 && dir_tf2==g_htfBias2) g_htfBias2=0;
   int htfAlign=(g_htfBias1==1 && g_htfBias2==1)?1:((g_htfBias1==-1 && g_htfBias2==-1)?-1:0);

   //--- m1 physics map ---
   bool m1ExpansionWeak=MapValI(m1o.t,m1o.expWeak,m1o.n,ct)!=0;
   g_m1ConvexityEmer  =MapValI(m1o.t,m1o.convEmer,m1o.n,ct)!=0;
   bool m1InductionEmer=MapValI(m1o.t,m1o.indEmer,m1o.n,ct)!=0;
   g_m1LiquidityEmer  =MapValI(m1o.t,m1o.liqEmer,m1o.n,ct)!=0;
   g_m1AbsorptionEmer =MapValI(m1o.t,m1o.absEmer,m1o.n,ct)!=0;

   //==============================================================
   // SECTION 4 -- MARKET STRUCTURE (chart TF)
   //==============================================================
   double structPivH=ChartPivotHigh(h,i,structLen);
   double structPivL=ChartPivotLow (l,i,structLen);
   if(!naf(structPivH)){ g_prevPivHigh=g_lastPivHigh; g_lastPivHigh=structPivH; }
   if(!naf(structPivL)){ g_prevPivLow =g_lastPivLow;  g_lastPivLow =structPivL; }
   bool isHH=!naf(g_lastPivHigh)&&!naf(g_prevPivHigh)&&g_lastPivHigh>g_prevPivHigh;
   bool isLH=!naf(g_lastPivHigh)&&!naf(g_prevPivHigh)&&g_lastPivHigh<g_prevPivHigh;
   bool isHL=!naf(g_lastPivLow )&&!naf(g_prevPivLow )&&g_lastPivLow >g_prevPivLow;
   bool isLL=!naf(g_lastPivLow )&&!naf(g_prevPivLow )&&g_lastPivLow <g_prevPivLow;
   double swPivH=ChartPivotHigh(h,i,pivotLen);
   double swPivL=ChartPivotLow (l,i,pivotLen);
   if(!naf(swPivH)){ g_prevSwingHigh=naf(g_currSwingHigh)?swPivH:g_currSwingHigh; g_currSwingHigh=swPivH; }
   if(!naf(swPivL)){ g_prevSwingLow =naf(g_currSwingLow )?swPivL:g_currSwingLow;  g_currSwingLow =swPivL; }
   bool bullBOS=!naf(g_prevSwingHigh)&&cl>g_prevSwingHigh;
   bool bearBOS=!naf(g_prevSwingLow )&&cl<g_prevSwingLow;
   bool bullCHoCH=!naf(g_prevSwingHigh)&&cl>g_prevSwingHigh+atr*chochBufferATR;
   bool bearCHoCH=!naf(g_prevSwingLow )&&cl<g_prevSwingLow -atr*chochBufferATR;
   if(useStrictStructure){
      if(isHH&&isHL) g_structBias=1;
      if(isLH&&isLL) g_structBias=-1;
   } else {
      if(bullBOS) g_structBias=1;
      if(bearBOS) g_structBias=-1;
   }
   int structBias=g_structBias;
   bool structLongOK =(!requireStruct)||(useStrictStructure&&structBias==1&&isHH)||(!useStrictStructure&&structBias==1);
   bool structShortOK=(!requireStruct)||(useStrictStructure&&structBias==-1&&isLL)||(!useStrictStructure&&structBias==-1);

   //==============================================================
   // SECTION 5 -- PIVOT MEMORY (chart, pivotLen)
   //==============================================================
   double pivH=swPivH, pivL=swPivL;
   double pivotEventPrice=NA; int pivotEventBar=-1,pivotEventDir=0;
   if(!naf(pivH)){ pivotEventPrice=pivH; pivotEventBar=i-pivotLen; pivotEventDir=1; }
   else if(!naf(pivL)){ pivotEventPrice=pivL; pivotEventBar=i-pivotLen; pivotEventDir=-1; }
   if(pivotEventDir!=0){
      g_prevPivotPrice=g_lastPivotPrice; g_prevPivotBar=g_lastPivotBar; g_prevPivotDir=g_lastPivotDir;
      g_lastPivotPrice=pivotEventPrice; g_lastPivotBar=pivotEventBar; g_lastPivotDir=pivotEventDir;
   }

   //==============================================================
   // SECTION 6 -- IMPULSE
   //==============================================================
   bool eliteShortImpulse=!naf(pivL)&&g_prevPivotDir==1 &&(g_prevPivotPrice-pivL)>atr*impulseAtrMult;
   bool eliteLongImpulse =!naf(pivH)&&g_prevPivotDir==-1&&(pivH-g_prevPivotPrice)>atr*impulseAtrMult;

   //==============================================================
   // PHYSICS OBSERVATION LAYER (Sec9 block)
   //==============================================================
   double velocityScore    =fmin2(MathAbs(velocity)    /fmax2(atr*0.1,1e-10)*50.0,100.0);
   double accelerationScore =fmin2(MathAbs(acceleration)/fmax2(atr*0.05,1e-10)*50.0,100.0);
   double convexityScore   =fmin2(MathAbs(convSmooth)  /fmax2(atr*convMult,1e-10)*25.0,100.0);
   double expansionScore   =fmin2(displacement/fmax2(dispThresh,1e-10)*50.0,100.0);
   double obs_ExpansionScore=fmin2(
        (efficiency>effThresh?efficiency*60.0:efficiency*30.0)+
        (displacement>dispThresh?(displacement/fmax2(dispThresh,1e-10)-1.0)*20.0:0.0)+
        ((velocity>0&&acceleration>0)||(velocity<0&&acceleration<0)?velocityScore*0.2:0.0),100.0);
   double obs_DecayScore=fmin2((bullMomDecay||bearMomDecay?40.0:0.0)+(convexityScore>30?convexityScore*0.5:0.0)+(phys_vd70?30.0:0.0),100.0);
   double obs_CurvatureScore=convexityScore;
   double obs_AbsorptionScore=fmin2(
        (efficiency<effThresh*0.7?(1.0-efficiency/fmax2(effThresh,1e-10))*50.0:0.0)+
        (phys_vd50?30.0:0.0)+(displacement<dispThresh*0.5?20.0:0.0),100.0);
   double obs_LiquidityScore=fmin2(obs_DecayScore*0.4+obs_CurvatureScore*0.4+
        (displacement>dispThresh*1.2&&(bullMomDecay||bearMomDecay)?20.0:0.0),100.0);
   double physicsMax =fmax2(obs_ExpansionScore,fmax2(obs_DecayScore,fmax2(obs_AbsorptionScore,obs_LiquidityScore)));
   double physicsMin =fmin2(obs_ExpansionScore,fmin2(obs_DecayScore,fmin2(obs_AbsorptionScore,obs_LiquidityScore)));
   double physicsDiff=physicsMax-physicsMin;
   double physicsConsensus=fmax2(0.0,100.0-physicsDiff);

   //==============================================================
   // ENGINE 1A  (lifecycle sourced from M5 fixed engine)
   //==============================================================
   string ie1a_currentPhase=l0_phaseCanon;
   double ie1a_phaseConfidence=fmax2(20.0,fmin2(100.0,fractalCtxScore*0.50+nz(se5_mf)*0.30+nz(se5_wp)*0.20));
   string ie1a_hypFamily=f_hypFam(ie1a_currentPhase);
   bool ie1a_isExpSide=(ie1a_currentPhase=="Expansion"||ie1a_currentPhase=="Expansion Pre-Convexity"||
        ie1a_currentPhase=="Expansion Induction"||ie1a_currentPhase=="Expansion Liquidity"||
        ie1a_currentPhase=="New High"||ie1a_currentPhase=="New Low");

   //==============================================================
   // ENERGY RESOLUTION FRAMEWORK (uses PREVIOUS-bar wave state)
   //==============================================================
   int direction=g_direction; // previous-bar direction (spawn runs later)
   int ede_state=(l0_phaseCanon=="Point 4 Origin"||l0_phaseCanon=="Expansion")?1:
        (l0_phaseCanon=="Expansion Pre-Convexity")?2:(l0_phaseCanon=="Expansion Induction")?3:
        (l0_phaseCanon=="Expansion Liquidity")?4:(l0_phaseCanon=="New High"||l0_phaseCanon=="New Low")?5:6;
   string ede_cleaningState=(ede_state==1)?"Accumulating":(ede_state==2)?"Cleaning - Initial Release":
        (ede_state==3)?"Cleaning - Secondary Release":(ede_state==4)?"Cleaning - Purge":(ede_state==5)?"Delivering":"Resolving";
   double ede_expansionEnergy=fmin2(obs_ExpansionScore*0.50+(bullImpulse||bearImpulse?30.0:0.0)+(efficiency*20.0),100.0);
   double ede_dissipatedEnergy=fmin2((ede_state>=2?obs_DecayScore*0.40:0.0)+(ede_state>=3?obs_CurvatureScore*0.30:0.0)+(ede_state>=4?obs_LiquidityScore*0.30:0.0),100.0);
   double ede_dissipationProgress=fmin2((ede_state>=2?25.0:0.0)+(ede_state>=3?25.0:0.0)+(ede_state>=4?25.0:0.0)+(ede_state>=5?25.0:0.0),100.0);
   bool ede_liquidationBecomingDirectional=(ede_state==4&&(bullImpulse||bearImpulse)&&efficiency>effThresh*0.8);
   double ede_deliverySpaceScore=fmin2(fmax2(0.0,100.0-g_convexityMaturity),100.0);
   bool ede_messyPriceIsDissipation=(ede_state>=2&&ede_state<=4)&&obs_DecayScore>30.0&&efficiency<effThresh*0.9&&!(bullImpulse||bearImpulse);
   int re_expectedCycles=MathMax(1,MathMin(g_waveDepth+2,4));
   int re_completedCycles=MathMax(0,MathMin(g_entryCycle,re_expectedCycles));
   double re_recursiveCompletionScore=re_expectedCycles>0?fmin2((double)re_completedCycles/(double)re_expectedCycles*100.0,100.0):0.0;
   double re_residualEnergy=fmax2(0.0,ede_expansionEnergy-ede_dissipatedEnergy);
   bool re_objectiveReached=ede_state>=5;
   bool re_fullDissipation=ede_dissipationProgress>=75.0;
   double re_dissipationProgress=ede_dissipationProgress;
   bool re_absorbedAndReturned=(ie1a_currentPhase=="Demand Return"||ie1a_currentPhase=="Supply Return")&&g_recursiveComplete;
   string re_resolutionState=(re_absorbedAndReturned&&re_fullDissipation&&re_recursiveCompletionScore>=75.0)?"RESOLVED":
        (re_objectiveReached&&re_dissipationProgress>=50.0)?"PARTIALLY RESOLVED":"UNRESOLVED";
   double re_residualEnergyScore=fmin2(re_residualEnergy,100.0);
   bool re_nodeOpen=re_resolutionState=="UNRESOLVED"||re_resolutionState=="PARTIALLY RESOLVED";
   double re_revisitProbability=re_resolutionState=="UNRESOLVED"?fmin2(re_residualEnergyScore*0.90,95.0):
        re_resolutionState=="PARTIALLY RESOLVED"?fmin2(re_residualEnergyScore*0.60,75.0):fmin2(re_residualEnergyScore*0.20,25.0);
   double eae_primaryAttractorPrice=direction==0?NA:
        re_resolutionState=="UNRESOLVED"?(direction==1?nz(g_flipBot,cl-atr*2.0):nz(g_flipTop,cl+atr*2.0)):
        re_resolutionState=="PARTIALLY RESOLVED"?(direction==1?nz(g_point4OriginLow,cl-atr):nz(g_point4OriginHigh,cl+atr)):NA;
   double eae_secondaryAttractorPrice=(direction!=0&&re_resolutionState=="UNRESOLVED"&&!naf(g_inducZoneLow)&&!naf(g_inducZoneHigh))?
        (direction==1?g_inducZoneLow:g_inducZoneHigh):NA;
   double eae_primaryAttractorScore=fmin2(re_residualEnergyScore*0.40+
        (re_resolutionState=="UNRESOLVED"?30.0:re_resolutionState=="PARTIALLY RESOLVED"?20.0:5.0)+
        (!naf(eae_primaryAttractorPrice)?fmax2(0.0,30.0-MathAbs(cl-eae_primaryAttractorPrice)/fmax2(atr,1e-10)*5.0):0.0),100.0);
   double eae_secondaryAttractorScore=fmin2(re_residualEnergyScore*0.25+
        (re_resolutionState=="PARTIALLY RESOLVED"?20.0:10.0)+
        (!naf(eae_secondaryAttractorPrice)?fmax2(0.0,20.0-MathAbs(cl-eae_secondaryAttractorPrice)/fmax2(atr,1e-10)*4.0):0.0),100.0);
   string eae_primaryAttractorLabel=re_resolutionState=="UNRESOLVED"?"Flip Zone (High Residual)":
        re_resolutionState=="PARTIALLY RESOLVED"?"Origin Zone (Partial)":"No Active Attractor";
   string eae_energyState=(ede_state==1)?"Accumulating":(ede_state>=2&&ede_state<=4)?"Cleaning":
        (ede_state==5)?"Delivering":(re_resolutionState=="RESOLVED")?"Exhausted":"Resolving";
   bool erf_activeDissipation=ede_messyPriceIsDissipation;
   bool erf_suppressRotation=erf_activeDissipation&&ede_state>=2&&ede_state<=4;
   double erf_confidence=fmin2((eae_energyState!="Accumulating"?ie1a_phaseConfidence*0.40:20.0)+
        (re_resolutionState=="RESOLVED"?30.0:re_resolutionState=="PARTIALLY RESOLVED"?20.0:10.0)+(eae_primaryAttractorScore*0.30),100.0);
   double erf_dissipationConfidence=fmin2((ede_messyPriceIsDissipation?50.0:0.0)+(ede_dissipationProgress*0.50),100.0);
   double erf_tradeReadiness=fmin2((re_resolutionState=="RESOLVED"?40.0:re_resolutionState=="PARTIALLY RESOLVED"?25.0:10.0)+
        re_recursiveCompletionScore*erfReadyResW+(100.0-re_residualEnergyScore)*erfReadyResidW+erf_confidence*erfReadyConfW,100.0);
   bool erf_entryGate=(!erfGateEnabled)||erf_tradeReadiness>=erfEntryThreshold;


   //==============================================================
   // SECTION 10 -- LIQUIDITY HEATMAP
   //==============================================================
   double _swH=nz(HighestN(h,i,liqSweepLookback),hi);
   double _swL=nz(LowestN (l,i,liqSweepLookback),lo);
   bool liqSweepBull=!naf(g_flipTop)&&_swH>g_flipTop;
   bool liqSweepBear=!naf(g_flipBot)&&_swL<g_flipBot;
   ArrayResize(g_volChart,ArraySize(g_volChart)+1); g_volChart[ArraySize(g_volChart)-1]=vol[i];
   double volAvg=SMAlastN(g_volChart,20);
   double normVol=(volAvg>0 && i-pivotLen>=0)?vol[i-pivotLen]/volAvg:1.0;
   if(!naf(pivH)||!naf(pivL)){
      double lvl=!naf(pivH)?pivH:pivL; int lType=!naf(pivH)?1:-1;
      double swRng=(i-pivotLen>=0)?(h[i-pivotLen]-l[i-pivotLen])/fmax2(atr,1e-10):0.0;
      double wt=normVol*swRng;
      int s=ArraySize(g_liqLevels);
      ArrayResize(g_liqLevels,s+1); ArrayResize(g_liqWeights,s+1); ArrayResize(g_liqAges,s+1); ArrayResize(g_liqTypes,s+1);
      g_liqLevels[s]=lvl; g_liqWeights[s]=wt; g_liqAges[s]=i-pivotLen; g_liqTypes[s]=lType;
   }
   if(ArraySize(g_liqLevels)>150){ ArrayRemove(g_liqLevels,0,1); ArrayRemove(g_liqWeights,0,1); ArrayRemove(g_liqAges,0,1); ArrayRemove(g_liqTypes,0,1); }
   double wDensity=0,wDensityAbove=0,wDensityBelow=0;
   double liqRadiusP=atr*liqRadius, liqRadiusWide=atr*liqRadius*3.0;
   int lsz=ArraySize(g_liqLevels);
   for(int q=0;q<lsz;q++){
      double lvl=g_liqLevels[q], wt=g_liqWeights[q]; int age=i-g_liqAges[q];
      double dcy=MathPow(liqAgDecay,age); double dist=MathAbs(cl-lvl);
      if(dist<liqRadiusP) wDensity+=wt*dcy;
      if(dist<liqRadiusWide){ if(lvl>cl) wDensityAbove+=wt*dcy*(1.0-dist/liqRadiusWide); else wDensityBelow+=wt*dcy*(1.0-dist/liqRadiusWide); }
   }
   double liqHeatRaw=fmin2((wDensityAbove+wDensityBelow)/2.0,5.0)/5.0*100.0;
   g_liqHeat=clamp(liqHeatRaw,0.0,100.0);
   double liqHeat=g_liqHeat;
   string liqZone=liqHeat<30?"Open space":liqHeat<70?"Active":"Congested";
   bool liqVacuum=wDensity<0.5;
   bool liqSweepOK=(!requireLiqSweep)||(direction==1&&(liqSweepBear||liqVacuum))||(direction==-1&&(liqSweepBull||liqVacuum));

   //==============================================================
   // SECTION 11 -- GEOMETRY
   //==============================================================
   int obAge=(g_obBirthBar>=0)?i-g_obBirthBar:0;
   bool obFresh=obAge<=obMaxBars;
   double obFreshness=(g_obBirthBar>=0)?fmax2(0.0,1.0-(double)obAge/(double)obMaxBars):0.0;
   double originToExtreme=NA;
   if(!naf(g_point4OriginHigh)&&!naf(g_point4OriginLow)){
      double orig=direction==1?g_point4OriginLow:g_point4OriginHigh;
      double extr=direction==1?nz(g_cycleHigh,orig):nz(g_cycleLow,orig);
      originToExtreme=MathAbs(extr-orig);
   }
   double flipzoneWidth=(!naf(g_flipTop)&&!naf(g_flipBot))?g_flipTop-g_flipBot:NA;
   double remainingRoom=NA;
   if(!naf(g_flipTop)&&!naf(g_flipBot)){ double fzMid=(g_flipTop+g_flipBot)/2.0; remainingRoom=fmin2(MathAbs(cl-fzMid)/fmax2(atr*4.0,1e-10)*100.0,100.0); }
   double availableSpace=remainingRoom;
   string cycleCapacity=naf(availableSpace)?"-":availableSpace>=60?"ROOM: HIGH":availableSpace>=30?"ROOM: MID":"ROOM: LOW";
   bool geoFullConvexityPossible=!naf(originToExtreme)&&!naf(flipzoneWidth)&&originToExtreme>atr*6.0&&flipzoneWidth<atr*3.0;
   bool geoPartialConvexityPossible=!naf(originToExtreme)&&originToExtreme>atr*3.0&&originToExtreme<=atr*6.0;
   bool geoAbsorptionOnly=!naf(originToExtreme)&&originToExtreme<=atr*3.0;
   double zonePrecision=!naf(flipzoneWidth)?fmax2(100.0-fmin2((flipzoneWidth/fmax2(atr*0.5,1e-10))*50.0,100.0),0.0):0.0;

   //==============================================================
   // SECTION 12 -- WAVE INTELLIGENCE
   //==============================================================
   double ref_effNorm =fmin2(efficiency,1.0);
   double ref_dispNorm=fmin2(displacement/fmax2(dispThresh*2.0,1e-10),1.0);
   double ref_velNorm =fmin2(MathAbs(velocity)/fmax2(atr*0.15,1e-10),1.0);
   double ref_curvNorm=fmin2(MathAbs(convSmooth)/fmax2(atr*convMult*2.0,1e-10),1.0);
   double sim_Expansion   =f_idealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.85,0.80,0.80,0.10);
   double sim_PreConv     =f_idealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.60,0.55,0.40,0.50);
   double sim_Induction   =f_idealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.65,0.60,0.30,0.60);
   double sim_Liquidity   =f_idealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.45,0.85,0.15,0.80);
   double sim_Creation    =f_idealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.30,0.70,0.05,0.90);
   double sim_Absorption  =f_idealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.20,0.25,0.10,0.40);
   double sim_Retracement =f_idealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.70,0.65,0.65,0.25);
   double sim_DemandReturn=f_idealSim(ref_effNorm,ref_dispNorm,ref_velNorm,ref_curvNorm,0.50,0.40,0.35,0.20);

   double waveTotalRange=!naf(originToExtreme)?originToExtreme:atr*5.0;
   double currentToFlipMid=(!naf(g_flipTop)&&!naf(g_flipBot))?MathAbs(cl-(g_flipTop+g_flipBot)/2.0):atr*4.0;
   double currentToExtreme=direction==1?MathAbs(nz(g_cycleHigh,cl+atr)-cl):MathAbs(cl-nz(g_cycleLow,cl-atr));
   double _posNormDen=fmax2(waveTotalRange,atr*0.5);
   double posDistToCreation   =fmin2(currentToExtreme/_posNormDen*100.0,100.0);
   double posDistToDemand     =fmin2(currentToFlipMid/_posNormDen*100.0,100.0);

   //--- velocity history for vel[2] ---
   ArrayResize(g_velHist,ArraySize(g_velHist)+1); g_velHist[ArraySize(g_velHist)-1]=velocity;
   double vel2=(ArraySize(g_velHist)>=3)?g_velHist[ArraySize(g_velHist)-3]:velocity;

   double expWeaknessScore=fmin2(((efficiency<effThresh?(1.0-efficiency/fmax2(effThresh,1e-10))*40.0:0.0)+
        (obs_DecayScore*0.30)+(MathAbs(velocity)<MathAbs(vel2)*0.6?20.0:0.0))*(100.0/90.0),100.0);
   double inductionMatScore=fmin2((g_inductionEvidence?35.0:0.0)+(obs_CurvatureScore*0.35)+(g_preConvEvidence?20.0:0.0)+
        (displacement>dispThresh*1.2&&(bullMomDecay||bearMomDecay)?10.0:0.0),100.0);
   double liqMatScore=fmin2((obs_LiquidityScore*0.50)+(liqSweepBull||liqSweepBear?30.0:0.0)+(liqHeat>60?20.0:liqHeat>30?10.0:0.0),100.0);
   double rawConvexityMaturity=fmin2(expWeaknessScore*0.35+inductionMatScore*0.35+liqMatScore*0.30,100.0);
   g_convexityMaturity=g_convexityMaturity+(2.0/(beliefSmooth+1))*(rawConvexityMaturity-g_convexityMaturity);
   double convexityMaturity=g_convexityMaturity;

   //==============================================================
   // ENGINE 1A -- DISPLAY-PHASE AUTHORITY (liqg overlay)
   //==============================================================
   bool _liqgRetr=ie1a_currentPhase=="Retracement Induction";
   bool _liqgArm =ie1a_currentPhase=="Expansion Induction"||_liqgRetr;
   // OWNER-DRIVEN DESTINATION: liqg target uses OWNER's destination, not local se5_tgt
   // Priority: H4 target > H1 target > M15 target > M5 target (owner curve hierarchy)
   double _liqgObj=MapVal(se240.t,se240.tgt,se240.n,ct);
   if(naf(_liqgObj)) _liqgObj=MapVal(se60.t,se60.tgt,se60.n,ct);
   if(naf(_liqgObj)) _liqgObj=MapVal(se15.t,se15.tgt,se15.n,ct);
   if(naf(_liqgObj)) _liqgObj=se5_tgt;
   if(_liqgArm && !g_liqg_active && !naf(_liqgObj)){
      g_liqg_active=true; g_liqg_isRetr=_liqgRetr; g_liqg_target=_liqgObj;
      g_liqg_dir=_liqgObj>cl?1:-1; g_liqg_initDist=fmax2(MathAbs(_liqgObj-cl),atr*0.5);
   }
   if(g_liqg_active && !naf(_liqgObj)) g_liqg_target=_liqgObj;
   double _liqgRemain=(g_liqg_active&&!naf(g_liqg_target))?MathAbs(g_liqg_target-cl):NA;
   double liqg_distPct=(g_liqg_active&&!naf(_liqgRemain))?fmin2(100.0,_liqgRemain/fmax2(g_liqg_initDist,1e-10)*100.0):NA;
   bool _liqgCapExh=ede_dissipationProgress>60||convexityMaturity>60;
   bool _liqgResolved=re_resolutionState=="RESOLVED";
   bool _liqgEnergyLo=efficiency<effThresh*0.7;
   bool _liqgMagnet=g_liqg_active&&!naf(liqg_distPct)&&liqg_distPct<20;
   bool _liqgArrStruct=g_liqg_active&&!naf(g_liqg_target)&&(g_liqg_dir==1?cl>=g_liqg_target:cl<=g_liqg_target);
   bool _liqgArrPhys=_liqgCapExh&&(_liqgResolved||_liqgMagnet);
   bool liqg_objArrival=_liqgArrStruct&&_liqgEnergyLo&&_liqgArrPhys;
   bool _liqgCounterBOS=g_liqg_dir==1?bearBOS:bullBOS;
   bool liqg_trueCHoCH=liqg_objArrival&&_liqgCounterBOS&&_liqgEnergyLo&&_liqgResolved;
   string liqg_subPhase=!g_liqg_active?"":liqg_objArrival?"Objective Arrival":
        (_liqgMagnet&&_liqgEnergyLo)?"Terminal Liquidation":
        (convexityMaturity>40||ede_dissipationProgress>40)?"Induction":
        (!naf(liqg_distPct)&&liqg_distPct<70)?"Displacement":
        (!naf(liqg_distPct)&&liqg_distPct<95)?"Push":"Initialization";
   string liqg_title=!g_liqg_active?"":
        (g_liqg_isRetr&&displayWaveDir_M5==-1)?"Pre-Supply Return Liquidation Wave":
        g_liqg_isRetr?"Pre-Demand Return Liquidation Wave":
        displayWaveDir_M5==-1?"Pre-New Low Liquidation Wave":"Pre-New High Liquidation Wave";
   bool _liqgInWindow=ie1a_currentPhase=="Expansion Induction"||ie1a_currentPhase=="Expansion Liquidity"||ie1a_currentPhase=="Retracement Induction"||ie1a_currentPhase=="Retracement Liquidity";
   if(g_liqg_active && (!_liqgInWindow||(liqg_objArrival&&liqg_trueCHoCH))) g_liqg_active=false;
   if(liqg_objArrival&&liqg_trueCHoCH) g_liqg_absorbUnlocked=true;
   if(ie1a_currentPhase=="Point 4 Origin") g_liqg_absorbUnlocked=false;
   string currentDisplayPhase=g_liqg_active?(liqg_title+(liqg_subPhase!=""?" - "+liqg_subPhase:"")):ie1a_currentPhase;
   bool _cdpSAgree=displayWaveDir_M5!=0&&(displayWaveDir_M5==1?cl>se5_inv:cl<se5_inv);
   bool _cdpMAgree=displayWaveDir_M5!=0&&(displayWaveDir_M5==1?velocity>0:velocity<0);
   bool _cdpPAgree=re_resolutionState!="RESOLVED"&&ede_dissipationProgress<80;
   double phaseConfidence=(_cdpSAgree?34.0:0.0)+(_cdpMAgree?33.0:0.0)+(_cdpPAgree?33.0:0.0);
   double phaseIntegrity=fmax2(0.0,fmin2(100.0,phaseConfidence*0.6+(100.0-fmin2(ede_dissipationProgress,100.0))*0.4));
   double _ppDistConsumed=(!naf(se5_tgt)&&!naf(se5_inv))?fmin2(100.0,MathAbs(cl-se5_inv)/fmax2(MathAbs(se5_tgt-se5_inv),1e-10)*100.0):NA;
   double phaseProgress=(g_liqg_active&&!naf(liqg_distPct))?(100.0-liqg_distPct):
        naf(_ppDistConsumed)?fmin2(100.0,ede_dissipationProgress*0.5+convexityMaturity*0.5):
        fmin2(100.0,_ppDistConsumed*0.5+convexityMaturity*0.3+ede_dissipationProgress*0.2);
   string liqg_arrTx=liqg_objArrival?"Yes":(!naf(liqg_distPct)&&liqg_distPct<12)?"Imminent":"No";

   //==============================================================
   // 12-WP / 12-FIT
   //==============================================================
   double _progressFromGeom=NA;
   if(!naf(g_point4OriginHigh)&&!naf(g_flipTop)&&!naf(g_flipBot)){
      double _origin=direction==1?g_point4OriginLow:g_point4OriginHigh;
      double _extreme=direction==1?nz(g_cycleHigh,cl+atr):nz(g_cycleLow,cl-atr);
      double _fzMid=(g_flipTop+g_flipBot)/2.0;
      double _totalMove=MathAbs(_extreme-_origin);
      double _toFzMid=MathAbs(_extreme-_fzMid);
      double _traveled=MathAbs(cl-_origin);
      double _expProg=_totalMove>1e-10?fmin2(_traveled/_totalMove*60.0,60.0):30.0;
      double _retrMove=MathAbs(cl-_extreme);
      double _retrProg=_toFzMid>1e-10?fmin2(_retrMove/fmax2(_toFzMid,1e-10)*40.0,40.0):0.0;
      double _retrWeight=fmin2(obs_AbsorptionScore/40.0,1.0);
      _progressFromGeom=_expProg+_retrProg*_retrWeight;
   }
   double _geomProgress=nz(_progressFromGeom,30.0);
   double _simAnchor=
        (sim_DemandReturn>=sim_Retracement&&sim_DemandReturn>=sim_Absorption&&sim_DemandReturn>=sim_Creation&&sim_DemandReturn>=sim_Expansion)?95.0:
        (sim_Retracement>=sim_Absorption&&sim_Retracement>=sim_Creation&&sim_Retracement>=sim_Expansion)?87.0:
        (sim_Absorption>=sim_Creation&&sim_Absorption>=sim_Expansion)?75.0:
        (sim_Creation>=sim_Liquidity&&sim_Creation>=sim_Expansion)?62.0:
        (sim_Liquidity>=sim_Induction&&sim_Liquidity>=sim_Expansion)?52.0:
        (sim_Induction>=sim_PreConv&&sim_Induction>=sim_Expansion)?43.0:
        (sim_PreConv>=sim_Expansion)?33.0:22.0;
   double _convWeight=fmax2(0.0,1.0-MathAbs(_simAnchor-47.5)/14.5);
   double _convAdjust=(convexityMaturity/100.0)*(_simAnchor-33.0)*0.50*_convWeight;
   double _physProgress=_simAnchor+_convAdjust;
   double rawWaveProgress=_geomProgress*0.60+_physProgress*0.40;
   g_waveProgress=g_waveProgress+(2.0/(beliefSmooth+1))*(rawWaveProgress-g_waveProgress);
   g_waveProgress=clamp(g_waveProgress,0.0,100.0);
   double waveProgress=g_waveProgress;
   double _bestSim=fmax2(sim_Expansion,fmax2(sim_PreConv,fmax2(sim_Induction,fmax2(sim_Liquidity,fmax2(sim_Creation,fmax2(sim_Absorption,fmax2(sim_Retracement,sim_DemandReturn)))))));
   double _geomConsistency=fmin2((!naf(originToExtreme)&&originToExtreme>atr*2.0?30.0:0.0)+
        (!naf(flipzoneWidth)&&flipzoneWidth<atr*4.0?25.0:0.0)+
        ((!naf(g_cycleHigh)||!naf(g_cycleLow))?20.0:0.0)+(direction!=0?25.0:0.0),100.0);
   double rawWaveModelFit=_bestSim*0.55+_geomConsistency*0.45;
   g_waveModelFit=g_waveModelFit+(2.0/(beliefSmooth+1))*(rawWaveModelFit-g_waveModelFit);
   g_waveModelFit=clamp(g_waveModelFit,0.0,100.0);
   double waveModelFit=g_waveModelFit;

   //==============================================================
   // 12A -- BELIEF ENGINE
   //==============================================================
   g_preConvEvidence=bullMomDecay||bearMomDecay;
   g_inductionEvidence=(direction==1&&bearImpulse&&g_nearFlipzone)||(direction==-1&&bullImpulse&&g_nearFlipzone);
   bool liquidityEvidence=obs_LiquidityScore>50.0&&obs_DecayScore>40.0;
   double _expPosMult=waveProgress<40.0?1.20:waveProgress<60.0?0.80:0.50;
   double rawExpansionBelief=fmin2((obs_ExpansionScore*0.45+(bullImpulse||bearImpulse?30.0:0.0)+(efficiency>effThresh*1.1?15.0:0.0)+sim_Expansion*0.10)*_expPosMult,100.0);
   double _convPosMult=(waveProgress>=30.0&&waveProgress<=65.0)?1.30:0.70;
   double rawConvexityBelief=fmin2((obs_DecayScore*0.30+obs_CurvatureScore*0.25+(g_preConvEvidence?15.0:0.0)+(g_inductionEvidence?10.0:0.0)+(liquidityEvidence?5.0:0.0)+convexityMaturity*0.08)*_convPosMult,100.0);
   double _creatPosMult=(waveProgress>=45.0&&waveProgress<=68.0)?1.40:0.60;
   double rawCreationBelief=fmin2(((convexityMaturity>50?convexityMaturity*0.12:0.0)+(obs_DecayScore>60?obs_DecayScore*0.20:0.0)+(obs_LiquidityScore>50?obs_LiquidityScore*0.20:0.0)+(obs_AbsorptionScore>20?obs_AbsorptionScore*0.15:0.0)+((!naf(g_cycleHigh)&&!naf(g_cycleLow)&&((direction==1&&hi>=nz(g_cycleHigh,hi)*0.998)||(direction==-1&&lo<=nz(g_cycleLow,lo)*1.002)))?20.0:0.0)+sim_Creation*0.10+(posDistToCreation<15.0?(15.0-posDistToCreation)*1.0:0.0))*_creatPosMult,100.0);
   double rawAbsorptionBelief=fmin2(obs_AbsorptionScore*0.50+(efficiency<effThresh*0.6?25.0:0.0)+(displacement<dispThresh*0.5?15.0:0.0)+sim_Absorption*0.10,100.0);
   double rawRetracementBelief=fmin2(((direction==1&&bearImpulse)||(direction==-1&&bullImpulse)?45.0:0.0)+(rawAbsorptionBelief>50?rawAbsorptionBelief*0.30:0.0)+(obs_CurvatureScore>40?15.0:0.0)+sim_Retracement*0.10,100.0);
   // Direction-aware liquidity sweep confirmation: longs confirmed by demand sweep (spring), shorts by supply sweep (trap)
   bool liqSweepConfirmsReturn=(direction==1&&liqSweepBear)||(direction==-1&&liqSweepBull);
   double rawDemandReturnBelief=fmin2(((!naf(g_flipTop)&&!naf(g_flipBot)&&cl<=g_flipTop&&cl>=g_flipBot)?35.0:0.0)+(rawRetracementBelief>60?rawRetracementBelief*0.30:0.0)+(liqHeat>50?liqHeat*0.15:0.0)+(liqSweepConfirmsReturn?20.0:0.0)+sim_DemandReturn*0.10,100.0);
   double bSmAlpha=2.0/(beliefSmooth+1);
   g_expansionBelief   +=bSmAlpha*(nz(rawExpansionBelief)   -g_expansionBelief);
   g_convexityBelief   +=bSmAlpha*(nz(rawConvexityBelief)   -g_convexityBelief);
   g_creationBelief    +=bSmAlpha*(nz(rawCreationBelief)    -g_creationBelief);
   g_absorptionBelief  +=bSmAlpha*(nz(rawAbsorptionBelief)  -g_absorptionBelief);
   g_retracementBelief +=bSmAlpha*(nz(rawRetracementBelief) -g_retracementBelief);
   g_demandReturnBelief+=bSmAlpha*(nz(rawDemandReturnBelief)-g_demandReturnBelief);
   double d_expansionBelief   =clamp(g_expansionBelief,0,100);
   double d_convexityBelief   =clamp(g_convexityBelief,0,100);
   double d_creationBelief    =clamp(g_creationBelief,0,100);
   double d_absorptionBelief  =clamp(g_absorptionBelief,0,100);
   double d_retracementBelief =clamp(g_retracementBelief,0,100);
   double d_demandReturnBelief=clamp(g_demandReturnBelief,0,100);
   double expansionBelief=g_expansionBelief, convexityBelief=g_convexityBelief, creationBelief=g_creationBelief;
   double absorptionBelief=g_absorptionBelief, retracementBelief=g_retracementBelief, demandReturnBelief=g_demandReturnBelief;

   //==============================================================
   // 12B -- PROXIMITY
   //==============================================================
   double expansionProximity=fmin2(sim_Expansion*0.50+(bullImpulse||bearImpulse?25.0:0.0)+(waveProgress<35.0?(35.0-waveProgress)*0.50:0.0)+(obs_ExpansionScore*0.25),100.0);
   double convexityProximity=fmin2(sim_PreConv*0.25+sim_Induction*0.25+sim_Liquidity*0.20+(g_preConvEvidence?15.0:0.0)+(waveProgress>=30.0&&waveProgress<=65.0?15.0:0.0),100.0);
   double creationProximity=fmin2(sim_Creation*0.50+(!naf(g_cycleHigh)&&direction==1&&hi>=nz(g_cycleHigh,hi)*0.995?25.0:0.0)+(!naf(g_cycleLow)&&direction==-1&&lo<=nz(g_cycleLow,lo)*1.005?25.0:0.0)+(convexityMaturity>60?convexityMaturity*0.25:0.0),100.0);
   double absorptionProximity=fmin2(sim_Absorption*0.50+(obs_AbsorptionScore*0.35)+(waveProgress>=68.0&&waveProgress<=80.0?15.0:0.0),100.0);
   double retracementProximity=fmin2(sim_Retracement*0.50+((direction==1&&bearImpulse)||(direction==-1&&bullImpulse)?30.0:0.0)+(waveProgress>=78.0&&waveProgress<=93.0?20.0:0.0),100.0);
   double demandReturnProximity=fmin2(sim_DemandReturn*0.50+(!naf(g_flipTop)&&!naf(g_flipBot)&&cl<=g_flipTop&&cl>=g_flipBot?30.0:0.0)+(waveProgress>=90.0?20.0:0.0),100.0);

   //==============================================================
   // 12D -- HYPOTHESIS
   //==============================================================
   double _fitMult=fmax2(0.60,waveModelFit/100.0);
   double hyp_LateExpansion=(expansionBelief*0.35+(waveProgress<38.0?(38.0-waveProgress)*0.80:0.0)+(convexityMaturity<30?(30.0-convexityMaturity)*0.30:0.0)+sim_Expansion*0.20+(expansionBelief>55&&convexityBelief>30?10.0:0.0))*_fitMult;
   double hyp_TerminalConvexity=(convexityBelief*0.30+(convexityMaturity>50?convexityMaturity*0.25:0.0)+(waveProgress>=38.0&&waveProgress<=62.0?20.0:0.0)+(sim_Induction+sim_Liquidity)*0.10+(posDistToCreation<25.0?(25.0-posDistToCreation)*0.50:0.0))*_fitMult;
   double hyp_CreationForming=(creationBelief*0.40+(convexityMaturity>65?(convexityMaturity-65.0)*0.40:0.0)+(posDistToCreation<15.0?(15.0-posDistToCreation)*1.50:0.0)+sim_Creation*0.20)*_fitMult;
   double hyp_AbsorptionActive=(absorptionBelief*0.45+(waveProgress>=68.0&&waveProgress<=80.0?20.0:0.0)+sim_Absorption*0.25+(g_m1AbsorptionEmer?10.0:0.0))*_fitMult;
   double hyp_RetracementActive=(retracementBelief*0.45+(waveProgress>=78.0&&waveProgress<=92.0?20.0:0.0)+sim_Retracement*0.25+((direction==1&&bearImpulse)||(direction==-1&&bullImpulse)?10.0:0.0))*_fitMult;
   double hyp_DemandReturn=(demandReturnBelief*0.45+(waveProgress>=88.0?(waveProgress-88.0)*1.20:0.0)+sim_DemandReturn*0.25+(g_closeInside?15.0:0.0))*_fitMult;
   double hyp_LateExpansion_N    =clamp(hyp_LateExpansion/105.0*100.0,0,100);
   double hyp_EarlyConvexity_N   =clamp(hyp_TerminalConvexity/108.0*100.0,0,100);
   double hyp_CreationForming_N  =clamp(hyp_CreationForming/97.0*100.0,0,100);
   double hyp_AbsorptionActive_N =clamp(hyp_AbsorptionActive/100.0*100.0,0,100);
   double hyp_RetracementActive_N=clamp(hyp_RetracementActive/100.0*100.0,0,100);
   double hyp_DemandReturn_N     =clamp(hyp_DemandReturn/100.0*100.0,0,100);
   string primaryHypothesis=ie1a_hypFamily;
   double primaryHypothesisConf=primaryHypothesis=="EXPANSION"?hyp_LateExpansion_N:
        primaryHypothesis=="CONVEXITY FORMING"?hyp_EarlyConvexity_N:
        primaryHypothesis=="CREATION FORMING"?hyp_CreationForming_N:
        primaryHypothesis=="ABSORPTION"?hyp_AbsorptionActive_N:
        primaryHypothesis=="RETRACEMENT"?hyp_RetracementActive_N:hyp_DemandReturn_N;

   //==============================================================
   // 12E -- PREDICTION
   //==============================================================
   double predScore_Expansion=(waveProgress<35.0?(35.0-waveProgress)*1.00:0.0)+(expansionBelief>55?expansionBelief*0.30:0.0)+(convexityMaturity<25?20.0:0.0)+(posDistToCreation>30?15.0:0.0)+(htfAlign==direction&&direction!=0?15.0:0.0);
   double predScore_Convexity=(waveProgress>=25.0&&waveProgress<=60.0?30.0:0.0)+(convexityMaturity>20?convexityMaturity*0.30:0.0)+(obs_DecayScore>40?20.0:0.0)+(g_m1ConvexityEmer?15.0:0.0)+(g_preConvEvidence?15.0:0.0);
   double predScore_Creation=(convexityMaturity>55?(convexityMaturity-55.0)*1.20:0.0)+(posDistToCreation<20.0?(20.0-posDistToCreation)*2.00:0.0)+(obs_LiquidityScore>55?20.0:0.0)+(liqSweepBull||liqSweepBear?15.0:0.0)+(g_m1LiquidityEmer?10.0:0.0);
   double predScore_Absorption=(predScore_Creation>50?predScore_Creation*0.40:0.0)+(obs_AbsorptionScore>35?obs_AbsorptionScore*0.30:0.0)+(g_m1AbsorptionEmer?20.0:0.0)+(waveProgress>=60.0&&waveProgress<=78.0?15.0:0.0);
   double predScore_Retracement=(absorptionBelief>45?absorptionBelief*0.35:0.0)+((direction==1&&bearMicroImpulse)||(direction==-1&&bullMicroImpulse)?25.0:0.0)+(waveProgress>=72.0&&waveProgress<=90.0?20.0:0.0)+(physicsConsensus<40?10.0:0.0);
   double predScore_DemandReturn=(retracementBelief>45?retracementBelief*0.35:0.0)+(posDistToDemand<20.0?(20.0-posDistToDemand)*1.50:0.0)+(liqSweepConfirmsReturn?20.0:0.0)+(waveProgress>=88.0?(waveProgress-88.0)*1.20:0.0);
   double _maxPredScore=fmax2(predScore_Expansion,fmax2(predScore_Convexity,fmax2(predScore_Creation,fmax2(predScore_Absorption,fmax2(predScore_Retracement,predScore_DemandReturn)))));
   string expectedNextPhase=
        (predScore_DemandReturn>=predScore_Retracement&&predScore_DemandReturn>=predScore_Absorption&&predScore_DemandReturn>=predScore_Creation&&predScore_DemandReturn>=predScore_Convexity&&predScore_DemandReturn>=predScore_Expansion)?(direction==-1?"Supply Return":"Demand Return"):
        (predScore_Retracement>=predScore_Absorption&&predScore_Retracement>=predScore_Creation&&predScore_Retracement>=predScore_Convexity&&predScore_Retracement>=predScore_Expansion)?"Retracement":
        (predScore_Absorption>=predScore_Creation&&predScore_Absorption>=predScore_Convexity&&predScore_Absorption>=predScore_Expansion)?"Transition Environment":
        (predScore_Creation>=predScore_Convexity&&predScore_Creation>=predScore_Expansion)?(direction==-1?"New Low":"New High"):
        (predScore_Convexity>=predScore_Expansion)?"Expansion Pre-Convexity":"Expansion";
   double expectedNextProb=_maxPredScore>0?fmin2(_maxPredScore/fmax2(_maxPredScore+30.0,1.0)*100.0,95.0):50.0;

   //==============================================================
   // 12F -- VALIDATION + 12G CONFIDENCE
   //==============================================================
   bool predTransition=ie1a_currentPhase!=g_lastIE1APhase;
   bool predSucceeded=predTransition&&ie1a_currentPhase==g_lastExpectedPhase;
   if(predTransition){ g_predOutcomes[g_predTotalIdx%100]=predSucceeded?1:0; g_predTotalIdx++; }
   g_lastExpectedPhase=expectedNextPhase; g_lastIE1APhase=ie1a_currentPhase;
   double predAcc10=PredAcc(10),predAcc25=PredAcc(25),predAcc50=PredAcc(50),predAcc100=PredAcc(100);
   double predReliability=predAcc10*0.4+predAcc25*0.3+predAcc50*0.2+predAcc100*0.1;
   double confIncrease=(predSucceeded?3.0:0.0)+(physicsConsensus>70?2.0:0.0)+(htfAlign==direction&&direction!=0?1.5:0.0)+(dir_tf1==dir_tf2&&dir_tf1!=0?1.0:0.0);
   double confDecrease=(predTransition&&!predSucceeded?2.0:0.0)+(physicsDiff>60?2.0:0.0)+(htfAlign!=direction&&direction!=0?1.5:0.0)+(dir_tf1!=dir_tf2&&dir_tf1!=0&&dir_tf2!=0?1.0:0.0);
   g_modelConfidence=fmax2(10.0,fmin2(100.0,g_modelConfidence+confIncrease-confDecrease-confDecayRate*(g_modelConfidence-50.0)));
   double modelConfidence=g_modelConfidence;
   double idealExpansionSig=efficiency, idealConvSig=obs_DecayScore/100.0, idealAbsSig=obs_AbsorptionScore/100.0;
   double waveDeviationRaw=MathAbs(idealExpansionSig-(ie1a_hypFamily=="EXPANSION"?0.85:0.30))*40.0+MathAbs(idealConvSig-(ie1a_hypFamily=="CONVEXITY FORMING"?0.70:0.20))*30.0+MathAbs(idealAbsSig-(ie1a_hypFamily=="ABSORPTION"?0.70:0.15))*30.0;
   double waveDeviation=fmin2(waveDeviationRaw*100.0,100.0);
   bool deviationAlert=waveDeviation>devReinterpThresh;
   int m1WarningScore=(m1ExpansionWeak?1:0)+(g_m1ConvexityEmer?1:0)+(m1InductionEmer?1:0)+(g_m1LiquidityEmer?1:0)+(g_m1AbsorptionEmer?1:0);
   string m1Warning=m1WarningScore>=4?"CRITICAL":m1WarningScore>=3?"HIGH":m1WarningScore>=2?"MODERATE":m1WarningScore>=1?"LOW":"CLEAR";
   double htf_ExpBelief =fmin2(expScr_tf2*0.5+expScr_tf1*0.5,100.0);
   double htf_ConvBelief=fmin2(decScr_tf2*0.4+curvScr_tf2*0.3+decScr_tf1*0.3,100.0);
   double htf_AbsBelief =fmin2(abScr_tf2*0.5+abScr_tf1*0.5,100.0);
   double htf_LiqBelief =fmin2(liqScr_tf2*0.5+liqScr_tf1*0.5,100.0);


   //==============================================================
   // SECTION 13 -- WAVE SPAWN ENGINE
   //==============================================================
   g_recursiveJustFired=false;
   bool _allowSpawn=l0_dir!=0 && l0_dir!=g_direction;
   if(_allowSpawn){
      int nd=l0_dir;
      double obTop=nd==1?g_lastPivotPrice:g_prevPivotPrice;
      double obBot=nd==1?g_prevPivotPrice:g_lastPivotPrice;
      int anchBar=g_prevPivotBar;
      double fzIP=FindInducPrice(h,l,i,anchBar,obTop,obBot,inducLookback);
      obTop=nz(se5_p4h,obTop); obBot=nz(se5_p4l,obBot);
      g_lastSpawnDir=nd; g_direction=nd; g_flipTop=obTop; g_flipBot=obBot;
      g_barsInZone=0; g_obBirthBar=i; g_contBar=-1;
      g_point4OriginHigh=obTop; g_point4OriginLow=obBot; g_point4OriginBar=i;
      g_flipzoneInducPrice=fzIP; g_flipzoneInducLow=naf(fzIP)?NA:fzIP-atr*inducZoneWidth; g_flipzoneInducHigh=naf(fzIP)?NA:fzIP+atr*inducZoneWidth;
      g_inducExpOriginHigh=NA; g_inducExpExtremeLow=NA; g_inducExpOriginLow=NA; g_inducExpExtremeHigh=NA;
      g_inducRetrOriginHigh=NA; g_inducRetrExtremeLow=NA; g_inducRetrOriginLow=NA; g_inducRetrExtremeHigh=NA;
      g_inducZoneLow=NA; g_inducZoneHigh=NA; g_cycleHigh=hi; g_cycleLow=lo;
      g_isRecursiveWave=false; g_entryCycle=0; g_waveDepth=0;
   }
   if(g_direction==1 && hi>nz(g_cycleHigh,hi)) g_cycleHigh=hi;
   if(g_direction==-1 && lo<nz(g_cycleLow,lo)) g_cycleLow=lo;

   bool expInducBuyEv =g_direction==1 && bearImpulse && structBias==1;
   bool expInducSellEv=g_direction==-1&& bullImpulse && structBias==-1;
   if(expInducBuyEv && naf(g_inducExpOriginHigh)){ g_inducExpOriginHigh=nz(g_point4OriginHigh,nz(g_cycleHigh,hi)); g_inducExpExtremeLow=lo; g_inducZoneLow=nz(g_point4OriginHigh,lo)-atr*inducZoneWidth; g_inducZoneHigh=nz(g_point4OriginHigh,lo)+atr*inducZoneWidth; }
   if(expInducSellEv && naf(g_inducExpOriginLow)){ g_inducExpOriginLow=nz(g_point4OriginLow,nz(g_cycleLow,lo)); g_inducExpExtremeHigh=hi; g_inducZoneLow=nz(g_point4OriginLow,hi)-atr*inducZoneWidth; g_inducZoneHigh=nz(g_point4OriginLow,hi)+atr*inducZoneWidth; }
   if(!naf(g_inducExpExtremeLow)&&g_direction==1&&lo<g_inducExpExtremeLow){ g_inducExpExtremeLow=lo; g_inducZoneLow=lo-atr*inducZoneWidth; g_inducZoneHigh=lo+atr*inducZoneWidth; }
   if(!naf(g_inducExpExtremeHigh)&&g_direction==-1&&hi>g_inducExpExtremeHigh){ g_inducExpExtremeHigh=hi; g_inducZoneLow=hi-atr*inducZoneWidth; g_inducZoneHigh=hi+atr*inducZoneWidth; }
   g_nearFlipzone=!naf(g_flipTop)&&!naf(g_flipBot)&&cl<=g_flipTop*1.02&&cl>=g_flipBot*0.98;
   bool nearFlipzone=g_nearFlipzone;
   bool retrInducBuyEv =g_direction==1 && bullImpulse && nearFlipzone;
   bool retrInducSellEv=g_direction==-1&& bearImpulse && nearFlipzone;
   if(retrInducBuyEv && naf(g_inducRetrOriginLow)){ g_inducRetrOriginLow=nz(g_cycleLow,lo); g_inducRetrExtremeHigh=hi; g_inducZoneLow=hi-atr*inducZoneWidth; g_inducZoneHigh=hi+atr*inducZoneWidth; }
   if(retrInducSellEv && naf(g_inducRetrOriginHigh)){ g_inducRetrOriginHigh=nz(g_cycleHigh,hi); g_inducRetrExtremeLow=lo; g_inducZoneLow=lo-atr*inducZoneWidth; g_inducZoneHigh=lo+atr*inducZoneWidth; }
   if(!naf(g_inducRetrExtremeHigh)&&g_direction==1&&hi>g_inducRetrExtremeHigh){ g_inducRetrExtremeHigh=hi; g_inducZoneLow=hi-atr*inducZoneWidth; g_inducZoneHigh=hi+atr*inducZoneWidth; }
   if(!naf(g_inducRetrExtremeLow)&&g_direction==-1&&lo<g_inducRetrExtremeLow){ g_inducRetrExtremeLow=lo; g_inducZoneLow=lo-atr*inducZoneWidth; g_inducZoneHigh=lo+atr*inducZoneWidth; }
   g_closeInside=!naf(g_flipTop)&&cl<=g_flipTop&&cl>=g_flipBot;
   bool priceInDemand=!naf(g_flipBot)&&lo<g_flipBot&&(!naf(g_point4OriginHigh)&&lo<=g_point4OriginHigh);
   bool priceInSupply=!naf(g_flipTop)&&hi>g_flipTop&&(!naf(g_point4OriginLow)&&hi>=g_point4OriginLow);
   bool trueCHoCH_bull=g_direction==1&&priceInDemand&&bullImpulse&&liqSweepOK;
   bool trueCHoCH_bear=g_direction==-1&&priceInSupply&&bearImpulse&&liqSweepOK;
   bool structFlipBull=g_direction==1&&bullConvShift&&structBias==-1;
   bool structFlipBear=g_direction==-1&&bearConvShift&&structBias==1;
   // v11: recursiveTrigger driven by ENGINES not phase labels
   // Uses se5_wp >= 85% as proxy for "curve at return/terminal" (available here, before v9 engines)
   bool recursiveTrigger=(trueCHoCH_bull||trueCHoCH_bear||structFlipBull||structFlipBear)&&(nz(se5_wp)>=85.0)&&(nz(MapVal(se5.t,se5.dom,se5.n,ct))>=40.0)&&g_direction!=0&&!naf(g_flipTop);
   if(recursiveTrigger&&(g_recursiveFiredBar<0||(i-g_recursiveFiredBar)>resetBars)){
      g_recursiveJustFired=true; g_recursiveFiredBar=i; g_recursiveComplete=true;
      int idx=MathMin(MathMax(g_entryCycle,1)-1,3);
      g_cycObTop[idx]=g_flipTop; g_cycObBot[idx]=g_flipBot; g_cycFlipTop[idx]=g_flipTop; g_cycFlipBot[idx]=g_flipBot;
      g_cycP4High[idx]=g_point4OriginHigh; g_cycP4Low[idx]=g_point4OriginLow; g_cycStartBar[idx]=g_point4OriginBar; g_cycDir[idx]=g_direction;
      g_waveGeneration++; g_entryCycle=MathMin(g_entryCycle+1,4); g_isRecursiveWave=true; g_waveDepth=g_entryCycle;
      int nd2=l0_dir!=0?l0_dir:((bullImpulse||bullConvShift)?1:-1);
      double obT2=nd2==1?g_lastPivotPrice:g_prevPivotPrice;
      double obB2=nd2==1?g_prevPivotPrice:g_lastPivotPrice;
      int anchBar2=g_prevPivotBar;
      double fzIP2=FindInducPrice(h,l,i,anchBar2,obT2,obB2,inducLookback);
      g_lastSpawnDir=nd2; g_direction=l0_dir!=0?l0_dir:nd2; g_flipTop=obT2; g_flipBot=obB2; g_barsInZone=0; g_obBirthBar=i;
      g_point4OriginHigh=obT2; g_point4OriginLow=obB2; g_point4OriginBar=i;
      g_flipzoneInducPrice=fzIP2; g_flipzoneInducLow=naf(fzIP2)?NA:fzIP2-atr*inducZoneWidth; g_flipzoneInducHigh=naf(fzIP2)?NA:fzIP2+atr*inducZoneWidth;
      g_inducExpOriginHigh=NA; g_inducExpExtremeLow=NA; g_inducExpOriginLow=NA; g_inducExpExtremeHigh=NA;
      g_inducRetrOriginHigh=NA; g_inducRetrExtremeLow=NA; g_inducRetrOriginLow=NA; g_inducRetrExtremeHigh=NA;
      g_inducZoneLow=NA; g_inducZoneHigh=NA; g_cycleHigh=hi; g_cycleLow=lo; g_contBar=i;
   }
   if(ie1a_currentPhase=="Demand Return"||ie1a_currentPhase=="Supply Return"){ g_barsInZone=g_closeInside?g_barsInZone+1:0; }
   int barsSinceCont=(g_contBar>=0)?i-g_contBar:((g_obBirthBar>=0)?i-g_obBirthBar:0);
   bool bullInvalid=g_direction==1&&cl<g_flipBot-atr*0.5;
   bool bearInvalid=g_direction==-1&&cl>g_flipTop+atr*0.5;
   bool opposingMove=(g_direction==1&&bearImpulse)||(g_direction==-1&&bullImpulse);
   bool hardInvalid=bullInvalid||bearInvalid;
   bool softReset=barsSinceCont>resetBars&&opposingMove&&(nz(se5_wp)<75.0)&&(nz(MapVal(se5.t,se5.dom,se5.n,ct))<30.0)&&!erf_suppressRotation;
   bool safeToReset=hardInvalid||softReset;
   if(g_direction!=l0_dir&&safeToReset){
      g_direction=0; g_lastSpawnDir=0; g_flipTop=NA; g_flipBot=NA; g_contBar=-1; g_obBirthBar=-1; g_barsInZone=0;
      g_isRecursiveWave=false; g_entryCycle=0; g_waveDepth=0; g_recursiveComplete=false;
   }
   direction=g_direction;
   bool recursiveComplete=g_recursiveComplete;
   double flipTop=g_flipTop, flipBot=g_flipBot, point4OriginHigh=g_point4OriginHigh, point4OriginLow=g_point4OriginLow;
   bool closeInside=g_closeInside;

   //==============================================================
   // SECTION 14 -- INDUCTION ZONE CLASSIFICATION
   //==============================================================
   bool inRetracementInducZone=!naf(pivL)&&!naf(g_inducZoneLow)&&!naf(g_inducZoneHigh)&&direction==1&&pivL>=g_inducZoneLow&&pivL<=g_inducZoneHigh&&retrInducBuyEv;
   bool inShortRetrInducZone=!naf(pivH)&&!naf(g_inducZoneLow)&&!naf(g_inducZoneHigh)&&direction==-1&&pivH>=g_inducZoneLow&&pivH<=g_inducZoneHigh&&retrInducSellEv;
   double inducConfidence=0.0;
   if(direction==1&&inRetracementInducZone) inducConfidence=1.0;
   else if(direction==1&&!naf(pivL)&&!naf(flipTop)&&!naf(flipBot)&&pivL<flipTop&&pivL>flipBot&&!inRetracementInducZone) inducConfidence=-0.5;
   else if(direction==-1&&inShortRetrInducZone) inducConfidence=1.0;
   else if(direction==-1&&!naf(pivH)&&!naf(flipTop)&&!naf(flipBot)&&pivH>flipBot&&pivH<flipTop&&!inShortRetrInducZone) inducConfidence=-0.5;
   bool retracementPreConvSeen=nearFlipzone&&(bullMomDecay||bearMomDecay);
   bool retracementInductionConf=inRetracementInducZone||inShortRetrInducZone;
   bool convexityComplete=g_creationBelief>50||g_absorptionBelief>40;
   int flipzoneStagesComplete=g_demandReturnBelief>75&&recursiveComplete?5:g_demandReturnBelief>60?4:g_retracementBelief>55?3:retracementInductionConf?2:retracementPreConvSeen?1:0;
   double flipzoneScore=flipzoneStagesComplete/5.0*100.0;

   //==============================================================
   // SECTION 15 -- SCORING
   //==============================================================
   double poiMid=(!naf(flipTop)&&!naf(flipBot))?(flipTop+flipBot)/2.0:NA;
   double energy=!naf(poiMid)?MathAbs(cl-poiMid)/fmax2(atr,1e-10):0.0;
   double sStruct=flipzoneScore*0.30;
   double sConv=fmin2(MathAbs(convSmooth)/fmax2(atr*convMult,1e-10)*25.0,25.0);
   double sEnergy=fmin2(energy*10.0,20.0);
   double sEff=efficiency*15.0;
   double sVol=fmin2((atr/fmax2(cl,1e-10))*1000.0,10.0);
   double contProb=fmin2(sStruct+sConv+sEnergy+sEff+sVol,100.0);
   string grade=contProb>90?"A+":contProb>80?"A":contProb>70?"B":contProb>60?"C":"D";
   color gradeCol=grade=="A+"?(color)0x88FF00:grade=="A"?clrLime:grade=="B"?clrYellow:grade=="C"?clrOrange:clrRed;

   //==============================================================
   // SECTION 16 -- BAYESIAN
   //==============================================================
   double bayesStruct=structBias==liveWaveDir?0.90:structBias==0?0.50:0.15;
   double bayesMomentum=(liveWaveDir==1&&velocity>0&&acceleration>0)?0.85:(liveWaveDir==-1&&velocity<0&&acceleration<0)?0.85:((liveWaveDir==1&&velocity>0)||(liveWaveDir==-1&&velocity<0))?0.60:0.30;
   double bayesLiq=liqHeat>70?0.80:liqHeat>30?0.55:0.35;
   double bayesHTF=liveHtfAlign==liveWaveDir&&liveHtfAlign!=0?0.90:liveHtfAlign==0?0.55:0.20;
   double bayesDisp=displacement>dispThresh*1.5?0.85:displacement>dispThresh?0.65:0.35;
   double bayesOB=obFreshness>0.7?0.80:obFreshness>0.4?0.60:0.35;
   double bayesInduc=inducConfidence>0?0.90:inducConfidence<0?0.20:0.50;
   double bayesFlipzone=flipzoneStagesComplete>=4?0.92:flipzoneStagesComplete>=3?0.75:flipzoneStagesComplete>=2?0.58:flipzoneStagesComplete>=1?0.42:0.25;
   double logOdds=0.15*MathLog(fmax2(bayesStruct,1e-10)/fmax2(1.0-bayesStruct,1e-10))+0.14*MathLog(fmax2(bayesMomentum,1e-10)/fmax2(1.0-bayesMomentum,1e-10))+0.10*MathLog(fmax2(bayesLiq,1e-10)/fmax2(1.0-bayesLiq,1e-10))+0.14*MathLog(fmax2(bayesHTF,1e-10)/fmax2(1.0-bayesHTF,1e-10))+0.11*MathLog(fmax2(bayesDisp,1e-10)/fmax2(1.0-bayesDisp,1e-10))+0.07*MathLog(fmax2(bayesOB,1e-10)/fmax2(1.0-bayesOB,1e-10))+0.12*MathLog(fmax2(bayesInduc,1e-10)/fmax2(1.0-bayesInduc,1e-10))+0.17*MathLog(fmax2(bayesFlipzone,1e-10)/fmax2(1.0-bayesFlipzone,1e-10));
   double finalProb=1.0/(1.0+MathExp(-logOdds))*100.0;

   //==============================================================
   // SECTION 17 -- PROBABILITY PANELS
   //==============================================================
   double velDecay=phys_vd70?1.0:0.0;
   double expansionProbability=fmin2((!bullInvalid&&!bearInvalid?20.0:0.0)+(convexityComplete?20.0:convexityScore*0.4)+(recursiveComplete?15.0:flipzoneStagesComplete*3.0)+(liveHtfAlign==liveWaveDir&&liveHtfAlign!=0?25.0:liveHtfAlign==0?12.5:0.0)+(liqHeat>50?20.0:liqHeat*0.4),100.0);
   double reversalProbability=fmin2((convexityScore>70?25.0:convexityScore*0.35)+(retracementInductionConf?20.0:0.0)+(liqHeat>70?20.0:0.0)+(velDecay*20.0)+(liveHtfAlign!=liveWaveDir&&liveHtfAlign!=0?15.0:0.0),100.0);
   double tradeReadiness=fmin2((liveWaveDir!=0?10.0:0.0)+(flipzoneStagesComplete>=3?15.0:flipzoneStagesComplete*5.0)+(velocityScore*0.10)+(expansionScore*0.10)+(liqHeat<50?10.0:liqHeat>70?-5.0:0.0)+(liveHtfAlign==liveWaveDir&&liveHtfAlign!=0?15.0:0.0)+(expansionProbability*0.20)+(bayesFlipzone*3.0),100.0);

   //==============================================================
   // SECTION 18 -- SLIPPAGE & TRADE OPPORTUNITY
   //==============================================================
   double spreadEstimate=atr*0.05;
   double volatilityFactor=volRatio*0.10;
   double slippageCost=atr*volatilityFactor+spreadEstimate;
   double liqDepthPenalty=liqHeat>70?atr*0.05:0.0;
   double totalSlippage=slippageCost+liqDepthPenalty;
   double baseTrend=efficiency*30;
   double impulseScore=displacement>dispThresh?20:0;
   double momentumScore=phys_mom>0?10:-10;
   double accelScore=acceleration>0?10:-10;
   double structScoreV=structBias==1?20:structBias==-1?-20:0;
   double htfScoreV=htfAlign==1?20:htfAlign==-1?-20:0;
   double liqScoreV=wDensity<0.5?10:-5;
   double zoneScore=closeInside?15:0;
   double inducScore=inducConfidence>0?10:inducConfidence<0?-10:0;
   double fzStageScore=flipzoneStagesComplete*6.0;
   double beliefBonus=(direction==1&&g_demandReturnBelief>60)?g_demandReturnBelief*0.10:(direction==-1&&g_demandReturnBelief>60)?g_demandReturnBelief*0.10:0.0;
   double confMult=fmax2(0.7,fmin2(modelConfidence/100.0*1.3,1.3));
   double buyScore=(baseTrend+impulseScore+fmax2(momentumScore,0)+fmax2(accelScore,0)+fmax2(structScoreV,0)+fmax2(htfScoreV,0)+liqScoreV+zoneScore+fmax2(inducScore,0)+fzStageScore+beliefBonus+(fractalStackDir==1?fractalCtxScore*0.30:0.0))*confMult;
   double sellScore=(baseTrend+impulseScore+fmax2(-momentumScore,0)+fmax2(-accelScore,0)+fmax2(-structScoreV,0)+fmax2(-htfScoreV,0)+liqScoreV+zoneScore+fmax2(-inducScore,0)+fzStageScore+beliefBonus+(fractalStackDir==-1?fractalCtxScore*0.30:0.0))*confMult;
   double netEdge=buyScore-sellScore;
   double netEdgeAdjusted=netEdge-(totalSlippage/fmax2(atr,1e-10)*10.0);
   bool edgePassesFilter=MathAbs(netEdgeAdjusted)>execThreshold;
   double buyProb=clamp(buyScore/279.5*100.0,0,100);
   double sellProb=clamp(sellScore/279.5*100.0,0,100);
   string liveDirective=netEdgeAdjusted>25?"BUY PRESSURE":netEdgeAdjusted>10?"BULLISH BIAS":netEdgeAdjusted<-25?"SELL PRESSURE":netEdgeAdjusted<-10?"BEARISH BIAS":"NEUTRAL / WAIT";

   //==============================================================
   // SECTION 19 -- HTF ALIGNMENT GATE / SECTION 20 -- EXEC LOCK
   //==============================================================
   bool htfAligned=direction!=0&&(htfAlign==direction||htfAlign==0);
   int resonance=htfAligned?2:1;
   int dynamicLockBars=(int)MathRound(baseLockBars*volMult);
   bool inducRearmLong=direction==1&&inRetracementInducZone;
   bool inducRearmShort=direction==-1&&inShortRetrInducZone;
   if(g_recursiveJustFired) g_engineArmed=true;
   if(inducRearmLong||inducRearmShort) g_engineArmed=true;
   bool withinGlobalLock=g_lastSignalBar>=0&&(i-g_lastSignalBar)<dynamicLockBars;
   bool withinLongLock=g_lastLongBar>=0&&(i-g_lastLongBar)<dynamicLockBars;
   bool withinShortLock=g_lastShortBar>=0&&(i-g_lastShortBar)<dynamicLockBars;
   bool signalLocked=withinGlobalLock&&!g_engineArmed;
   bool htfLongOK=(!requireHTFAlign)||(g_htfBias1>=0&&g_htfBias2>=0);
   bool htfShortOK=(!requireHTFAlign)||(g_htfBias1<=0&&g_htfBias2<=0);
   bool preConvOK_long=(!requirePreConv)||retracementPreConvSeen;
   bool preConvOK_short=(!requirePreConv)||retracementPreConvSeen;
   bool inducOK_long=(!requireInduction)||retracementInductionConf;
   bool inducOK_short=(!requireInduction)||retracementInductionConf;

   //==============================================================
   // SECTION 21 -- ENTRY SIGNALS
   //==============================================================
   // --- INLINE ENTRY READINESS (runs every bar, not just isLast) ---
   // Map dominance transfer + recursion from key rungs for entry qualification
   double _inl_dom_m1 =nz(MapVal(se1.t,se1.dom,se1.n,ct));
   double _inl_dom_m3 =nz(MapVal(se3.t,se3.dom,se3.n,ct));
   double _inl_dom_m5 =nz(MapVal(se5.t,se5.dom,se5.n,ct));
   double _inl_dom_m15=nz(MapVal(se15.t,se15.dom,se15.n,ct));
   double _inl_dom_h1 =nz(MapVal(se60.t,se60.dom,se60.n,ct));
   int _inl_ph_m1=(int)nz(se1_ph), _inl_ph_m3=(int)nz(se3_ph), _inl_ph_m5=(int)nz(se5_ph);
   int _inl_ph_m15=(int)nz(se15_ph), _inl_ph_h1=(int)nz(se60_ph);

   // ===== CALIBRATED ENTRY QUALITY GATES (per Image 1+2 reference pattern) =====
   // The PERFECT sell has: H4 Bear, dom=100%, atFlip=Y, ALL TFs bearish, terminal DONE, FU=Y
   // We filter out garbage entries that don't have these characteristics.

   // GATE 1: FLIP ZONE PROXIMITY -- must be AT or INSIDE the flip zone (not random retracement)
   bool _atFlipZone = g_nearFlipzone || g_closeInside;

   // GATE 2: HIGH DOMINANCE -- require M5 specifically >=75% (the execution timeframe)
   // The bad buy had dom=56% on M5 but passed because H1 was high. M5 is what matters for execution.
   // Fallback: if M5 is 60%+ AND a higher rung is 75%+, also acceptable (anticipatory from HTF)
   bool _highDomM5plus = _inl_dom_m5>=75.0 || (_inl_dom_m5>=60.0 && (_inl_dom_m15>=75.0||_inl_dom_h1>=75.0));

   // GATE 3: MULTI-TF ALIGNMENT -- calibrated for BOTH scenarios:
   //   A) Strong: 3+ of 6 TFs aligned (clear directional consensus)
   //   B) Anticipatory: 2+ TFs aligned + high dominance (transition completing, HTFs about to flip)
   // The good sell at H1 supply had: M1+M5 bearish (2) + dom=89% = anticipatory entry BEFORE H1/H4 flip
   // Include ALL rungs (M1,M3,M5,M15,H1,H4) for full picture
   int _tfAlignLong  = (m1_dir==1?1:0)+(l3_dir==1?1:0)+(l0_dir==1?1:0)+(l1_dir==1?1:0)+(l2_dir==1?1:0)+(l4_dir==1?1:0);
   int _tfAlignShort = (m1_dir==-1?1:0)+(l3_dir==-1?1:0)+(l0_dir==-1?1:0)+(l1_dir==-1?1:0)+(l2_dir==-1?1:0)+(l4_dir==-1?1:0);
   bool _multiTfLong  = (_tfAlignLong >= 3) || (_tfAlignLong >= 2 && _highDomM5plus);
   bool _multiTfShort = (_tfAlignShort >= 3) || (_tfAlignShort >= 2 && _highDomM5plus);

   // GATE 4: TERMINAL SEQUENCE -- must be in terminal phases or Return (not early expansion/retracement)
   bool _anyRungInReturn = (_inl_ph_m1==12||_inl_ph_m1==13)||(_inl_ph_m3==12||_inl_ph_m3==13)||
        (_inl_ph_m5==12||_inl_ph_m5==13)||(_inl_ph_m15==12||_inl_ph_m15==13)||(_inl_ph_h1==12||_inl_ph_h1==13);
   bool _anyRungInTerminal = (_inl_ph_m1>=9&&_inl_ph_m1<=11)||(_inl_ph_m3>=9&&_inl_ph_m3<=11)||
        (_inl_ph_m5>=9&&_inl_ph_m5<=11)||(_inl_ph_m15>=9&&_inl_ph_m15<=11)||(_inl_ph_h1>=9&&_inl_ph_h1<=11);
   bool _terminalOrReturn = _anyRungInReturn || _anyRungInTerminal;

   // GATE 5: FU OR STRUCTURAL CONFIRMATION -- FU candle active OR strong structural evidence
   // Check FU blocks directly from global arrays (die_anyBullFUActive declared later in code)
   bool _fuConfirmLong=false, _fuConfirmShort=false;
   for(int _fq=ArraySize(g_fu_top)-1;_fq>=0;_fq--){
      if((i-g_fu_birthBar[_fq])<=fuMaxBarsActive && g_fu_state[_fq]!="Invalidated"){
         if(g_fu_dir[_fq]==1) _fuConfirmLong=true;
         if(g_fu_dir[_fq]==-1) _fuConfirmShort=true;
      }
   }
   bool _structConfirmLong  = liqSweepOK && retracementInductionConf;
   bool _structConfirmShort = liqSweepOK && retracementInductionConf;
   bool _confirmationLong  = _fuConfirmLong || _structConfirmLong;
   bool _confirmationShort = _fuConfirmShort || _structConfirmShort;

   // GATE 6: MULTI-CURVE FLIP CONTEXT -- the universal rule from spec:
   //   ALL curves have a flip zone. BUYS happen BELOW it. SELLS happen ABOVE it.
   //   Use the highest available TF flip zone as context authority (H4 > H1 > M15 > M5).
   //   This ensures the algo always knows WHERE it is relative to the key reversal point.
   double _ctx_ft=NA, _ctx_fb=NA, _ctx_flipMid=NA;
   // H4 flip zone (highest authority)
   double _ft_h4=MapVal(se240.t,se240.ft,se240.n,ct), _fb_h4=MapVal(se240.t,se240.fb,se240.n,ct);
   if(!naf(_ft_h4)&&!naf(_fb_h4)){ _ctx_ft=_ft_h4; _ctx_fb=_fb_h4; _ctx_flipMid=(_ft_h4+_fb_h4)/2.0; }
   // Fallback H1
   if(naf(_ctx_flipMid)){
      double _ft_h1=MapVal(se60.t,se60.ft,se60.n,ct), _fb_h1=MapVal(se60.t,se60.fb,se60.n,ct);
      if(!naf(_ft_h1)&&!naf(_fb_h1)){ _ctx_ft=_ft_h1; _ctx_fb=_fb_h1; _ctx_flipMid=(_ft_h1+_fb_h1)/2.0; }
   }
   // Fallback M15
   if(naf(_ctx_flipMid)){
      double _ft_m15=MapVal(se15.t,se15.ft,se15.n,ct), _fb_m15=MapVal(se15.t,se15.fb,se15.n,ct);
      if(!naf(_ft_m15)&&!naf(_fb_m15)){ _ctx_ft=_ft_m15; _ctx_fb=_fb_m15; _ctx_flipMid=(_ft_m15+_fb_m15)/2.0; }
   }
   // Fallback M5 (chart-level spawn)
   if(naf(_ctx_flipMid) && !naf(g_flipTop) && !naf(g_flipBot)){
      _ctx_ft=g_flipTop; _ctx_fb=g_flipBot; _ctx_flipMid=(g_flipTop+g_flipBot)/2.0;
   }
   // FLIP CONTEXT RULE: below flip = buy territory, above flip = sell territory
   // Allow small buffer (0.3 ATR) for entries right at the zone edge
   bool _flipCtxAllowLong  = naf(_ctx_flipMid) || (cl <= _ctx_flipMid + atr*0.3);
   bool _flipCtxAllowShort = naf(_ctx_flipMid) || (cl >= _ctx_flipMid - atr*0.3);
   // Store for EA TryEnter() access
   cur_ctxFlipTop=_ctx_ft; cur_ctxFlipBot=_ctx_fb; cur_ctxFlipMid=_ctx_flipMid;
   // --- POPULATE PER-TIMEFRAME CURVE CONTEXT (V60 port: origin->extreme->flip per curve) ---
   // Each curve knows: where it was born, where its peak/trough is, and its flip zone.
   // This gives the algo full awareness of which curves it's working within.
   cur_cv_dir[0]=m1_dir; cur_cv_origin[0]=se1_inv;
   cur_cv_extreme[0]=(m1_dir==1?nz(MapVal(se1.t,se1.sh,se1.n,ct)):m1_dir==-1?nz(MapVal(se1.t,se1.sl,se1.n,ct)):NA);
   cur_cv_flipTop[0]=MapVal(se1.t,se1.ft,se1.n,ct); cur_cv_flipBot[0]=MapVal(se1.t,se1.fb,se1.n,ct);
   cur_cv_flipMid[0]=(!naf(cur_cv_flipTop[0])&&!naf(cur_cv_flipBot[0]))?(cur_cv_flipTop[0]+cur_cv_flipBot[0])/2.0:NA;
   cur_cv_wp[0]=nz(MapVal(se1.t,se1.wp,se1.n,ct)); cur_cv_dom[0]=_inl_dom_m1; cur_cv_comp[0]=nz(MapVal(se1.t,se1.comp,se1.n,ct)); cur_cv_phase[0]=_inl_ph_m1;

   cur_cv_dir[1]=l3_dir; cur_cv_origin[1]=se3_inv;
   cur_cv_extreme[1]=(l3_dir==1?nz(MapVal(se3.t,se3.sh,se3.n,ct)):l3_dir==-1?nz(MapVal(se3.t,se3.sl,se3.n,ct)):NA);
   cur_cv_flipTop[1]=MapVal(se3.t,se3.ft,se3.n,ct); cur_cv_flipBot[1]=MapVal(se3.t,se3.fb,se3.n,ct);
   cur_cv_flipMid[1]=(!naf(cur_cv_flipTop[1])&&!naf(cur_cv_flipBot[1]))?(cur_cv_flipTop[1]+cur_cv_flipBot[1])/2.0:NA;
   cur_cv_wp[1]=nz(MapVal(se3.t,se3.wp,se3.n,ct)); cur_cv_dom[1]=_inl_dom_m3; cur_cv_comp[1]=nz(MapVal(se3.t,se3.comp,se3.n,ct)); cur_cv_phase[1]=_inl_ph_m3;

   cur_cv_dir[2]=l0_dir; cur_cv_origin[2]=se5_inv;
   cur_cv_extreme[2]=(l0_dir==1?nz(MapVal(se5.t,se5.sh,se5.n,ct)):l0_dir==-1?nz(MapVal(se5.t,se5.sl,se5.n,ct)):NA);
   cur_cv_flipTop[2]=MapVal(se5.t,se5.ft,se5.n,ct); cur_cv_flipBot[2]=MapVal(se5.t,se5.fb,se5.n,ct);
   cur_cv_flipMid[2]=(!naf(cur_cv_flipTop[2])&&!naf(cur_cv_flipBot[2]))?(cur_cv_flipTop[2]+cur_cv_flipBot[2])/2.0:NA;
   cur_cv_wp[2]=nz(se5_wp); cur_cv_dom[2]=_inl_dom_m5; cur_cv_comp[2]=nz(MapVal(se5.t,se5.comp,se5.n,ct)); cur_cv_phase[2]=_inl_ph_m5;

   cur_cv_dir[3]=l1_dir; cur_cv_origin[3]=se15_inv;
   cur_cv_extreme[3]=(l1_dir==1?nz(MapVal(se15.t,se15.sh,se15.n,ct)):l1_dir==-1?nz(MapVal(se15.t,se15.sl,se15.n,ct)):NA);
   cur_cv_flipTop[3]=MapVal(se15.t,se15.ft,se15.n,ct); cur_cv_flipBot[3]=MapVal(se15.t,se15.fb,se15.n,ct);
   cur_cv_flipMid[3]=(!naf(cur_cv_flipTop[3])&&!naf(cur_cv_flipBot[3]))?(cur_cv_flipTop[3]+cur_cv_flipBot[3])/2.0:NA;
   cur_cv_wp[3]=nz(se15_wp); cur_cv_dom[3]=_inl_dom_m15; cur_cv_comp[3]=nz(MapVal(se15.t,se15.comp,se15.n,ct)); cur_cv_phase[3]=_inl_ph_m15;

   cur_cv_dir[4]=l2_dir; cur_cv_origin[4]=se60_inv;
   cur_cv_extreme[4]=(l2_dir==1?nz(MapVal(se60.t,se60.sh,se60.n,ct)):l2_dir==-1?nz(MapVal(se60.t,se60.sl,se60.n,ct)):NA);
   cur_cv_flipTop[4]=MapVal(se60.t,se60.ft,se60.n,ct); cur_cv_flipBot[4]=MapVal(se60.t,se60.fb,se60.n,ct);
   cur_cv_flipMid[4]=(!naf(cur_cv_flipTop[4])&&!naf(cur_cv_flipBot[4]))?(cur_cv_flipTop[4]+cur_cv_flipBot[4])/2.0:NA;
   cur_cv_wp[4]=nz(se60_wp); cur_cv_dom[4]=_inl_dom_h1; cur_cv_comp[4]=nz(MapVal(se60.t,se60.comp,se60.n,ct)); cur_cv_phase[4]=_inl_ph_h1;

   cur_cv_dir[5]=l4_dir; cur_cv_origin[5]=se240_inv;
   cur_cv_extreme[5]=(l4_dir==1?nz(MapVal(se240.t,se240.sh,se240.n,ct)):l4_dir==-1?nz(MapVal(se240.t,se240.sl,se240.n,ct)):NA);
   cur_cv_flipTop[5]=MapVal(se240.t,se240.ft,se240.n,ct); cur_cv_flipBot[5]=MapVal(se240.t,se240.fb,se240.n,ct);
   cur_cv_flipMid[5]=(!naf(cur_cv_flipTop[5])&&!naf(cur_cv_flipBot[5]))?(cur_cv_flipTop[5]+cur_cv_flipBot[5])/2.0:NA;
   cur_cv_wp[5]=nz(MapVal(se240.t,se240.wp,se240.n,ct)); cur_cv_dom[5]=nz(MapVal(se240.t,se240.dom,se240.n,ct)); cur_cv_comp[5]=nz(MapVal(se240.t,se240.comp,se240.n,ct)); cur_cv_phase[5]=(int)nz(se240_ph);

   // ???????????????????????????????????????????????????????
   // GATE 7: UNIFIED OWNERSHIP DEATH ENGINE (4-signal convergence)
   // Replaces single-variable Gate 7. Old: _macroDom>50 alone (5-15 bar lag).
   // New: triangulate from 4 independent sources. Requires 2+ to agree.
   //
   // SIGNAL 1 -- SE engine dom (slow/structural):
   //   The SE recBrk counter crossed majority (>40%). Lagging but reliable.
   //   Threshold lowered to 40% (not 50%) because we require convergence,
   //   so we don't need this signal alone to be conclusive.
   //
   // SIGNAL 2 -- LTF structural reversal (fast/structural):
   //   2+ lower timeframes have reversed against the macro direction.
   //   M5 bearish + M1 bearish while H4 is bullish = visible structure reversed.
   //
   // SIGNAL 3 -- HOE opposing weight (composite/current):
   //   30%+ of collective TF weight is now in the OPPOSITE direction.
   //   Computed from cur_cv_dir[] which is available in Section 21.
   //
   // SIGNAL 4 -- V60 curve life (composite/fast):
   //   ctx_life < InpCurveDeadBelow (default 32). Multiple inputs combined.
   //   When life is DEAD, the curve's energy, force and retrace all confirm death.
   // ???????????????????????????????????????????????????????
   int _macroDir = (l4_dir!=0) ? l4_dir : (l2_dir!=0) ? l2_dir : fractalStackDir;
   double _macroDom = (l4_dir!=0) ? nz(MapVal(se240.t,se240.dom,se240.n,ct)) :
                      (l2_dir!=0) ? nz(MapVal(se60.t,se60.dom,se60.n,ct)) :
                      nz(MapVal(se5.t,se5.dom,se5.n,ct));
   double _macroWP = (l4_dir!=0) ? cur_cv_wp[5] : (l2_dir!=0) ? cur_cv_wp[4] : cur_cv_wp[2];

   // --- 4 independent death signals, each scored 0 or 1 ---
   // Signal 1: SE dom crossed 40% (lagging, structural)
   bool _ds1_seDom = _macroDom > 40.0;
   // Signal 2: LTF structural reversal count
   int _ltfCountAgainst = 0;
   if(m1_dir!=0 && m1_dir!=_macroDir) _ltfCountAgainst++;
   if(l3_dir!=0 && l3_dir!=_macroDir) _ltfCountAgainst++;
   if(l0_dir!=0 && l0_dir!=_macroDir) _ltfCountAgainst++;
   if(l1_dir!=0 && l1_dir!=_macroDir) _ltfCountAgainst++;
   if(l2_dir!=0 && l2_dir!=_macroDir && _macroDir==l4_dir) _ltfCountAgainst++; // H1 vs H4
   bool _ds2_ltfRev = _ltfCountAgainst >= 2;
   // Signal 3: HOE opposing weight (quick calc from cur_cv_dir[], available here)
   int _oppDir = -_macroDir;
   double _oppWeight = 0.0, _totWeight = 0.0;
   double _hoeWts[6]; _hoeWts[0]=0.20; _hoeWts[1]=0.35; _hoeWts[2]=0.55; _hoeWts[3]=0.70; _hoeWts[4]=0.85; _hoeWts[5]=1.0;
   for(int _qi=0;_qi<6;_qi++){
      _totWeight += _hoeWts[_qi];
      if(cur_cv_dir[_qi]==_oppDir) _oppWeight += _hoeWts[_qi];
   }
   bool _ds3_hoeOpp = _totWeight>0 && (_oppWeight/_totWeight)>0.30;
   // Signal 4: V60 curve life says DEAD
   bool _ds4_lifeDead = ctx_life < (double)InpCurveDeadBelow;
   // Count death signals
   int _deathSignalsLong  = ((!_ds1_seDom)?0:1) + (_ds2_ltfRev&&_macroDir==-1?1:0) + (_ds3_hoeOpp&&_oppDir==1?1:0) + (_ds4_lifeDead?1:0);
   int _deathSignalsShort = ((!_ds1_seDom)?0:1) + (_ds2_ltfRev&&_macroDir==1?1:0) + (_ds3_hoeOpp&&_oppDir==-1?1:0) + (_ds4_lifeDead?1:0);
   // Generic death count (max of both directions, for display)
   int _totalDeathSignals = MathMax(_deathSignalsLong, _deathSignalsShort);
   cur_ownerDeathSignals = _totalDeathSignals;
   // 2+ signals = curve is dying, allow counter-trend entries
   bool _ownerDeadForLong  = (_macroDir==-1) && (_deathSignalsLong  >= 2);
   bool _ownerDeadForShort = (_macroDir==1)  && (_deathSignalsShort >= 2);
   // Legacy anticipatory path (very high dom + terminal phase = immediate override)
   bool _anticipatoryLong  = (_inl_dom_m5>=80.0||_inl_dom_m15>=80.0||_inl_dom_h1>=80.0) && (_anyRungInReturn||_inl_ph_m5>=10||_inl_ph_m1>=10);
   bool _anticipatoryShort = (_inl_dom_m5>=80.0||_inl_dom_m15>=80.0||_inl_dom_h1>=80.0) && (_anyRungInReturn||_inl_ph_m5>=10||_inl_ph_m1>=10);
   bool _allowLong  = (_macroDir==1)  || (_macroDir==0) || _anticipatoryLong  || _ownerDeadForLong;
   bool _allowShort = (_macroDir==-1) || (_macroDir==0) || _anticipatoryShort || _ownerDeadForShort;

   // COMBINED ENTRY READINESS -- v12 AUDIT FIX
   // DEAD variables wired: _eceEntryConf, cur_curveBudget, cur_recDepth all now contribute.
   // Uses SE-available data (computed before isLast):
   double _se5DomNow = nz(MapVal(se5.t,se5.dom,se5.n,ct));
   double _se5WPnow = nz(se5_wp);
   // Execution confidence proxy from available data
   double _execConfProxy = fmin2(100.0, _se5DomNow*0.35 + _se5WPnow*0.35 +
        (double)fmin2(_inl_dom_m5,_inl_dom_m15)*0.15 + (_anyRungInTerminal||_anyRungInReturn?15.0:0.0));
   // Curve capacity: budget<25% = close to target = higher readiness
   double _budgetBonus = (cur_curveBudget>0.0 && cur_curveBudget<25.0) ? 15.0 : 0.0;
   // Recursion depth: each counted recursion = old curve consuming its geometry
   double _recBonus = fmin2(20.0, (double)cur_recDepth*5.0);
   // When ownership death is confirmed (2+ signals), _terminalOrReturn is not required:
   // the death signals themselves confirm the curve is in its terminal stage.
   bool _ownerDeathConfirmed = cur_ownerDeathSignals >= 2;
   bool _entryReadyGate = _highDomM5plus && (_terminalOrReturn || _ownerDeathConfirmed) && (_execConfProxy + _budgetBonus + _recBonus >= 30.0);

   // v12: entry driven by engines only -- no phase belief scores
   bool beliefEntryLong=_allowLong&&direction==1&&_entryReadyGate&&_multiTfLong&&_confirmationLong&&_flipCtxAllowLong;
   bool beliefEntryShort=_allowShort&&direction==-1&&_entryReadyGate&&_multiTfShort&&_confirmationShort&&_flipCtxAllowShort;
   // When ownership death confirmed, bypass ERF gate (the ownership signal IS the readiness confirmation)
   bool _erfBypass = _ownerDeathConfirmed && (cur_ownerDeathSignals >= 3 || _ds4_lifeDead);
   // ENTRY SIGNALS -- ownership death + curve context only, no ERF/DOE/grade/opp blocking
   bool longSignal=showSignals&&beliefEntryLong&&!signalLocked&&!withinLongLock&&obFresh;
   bool shortSignal=showSignals&&beliefEntryShort&&!signalLocked&&!withinShortLock&&obFresh;

   // ===== LAYER 2: CONTINUATION HUNT MODE (demand/supply expansion entries) =====
   // After a flip zone trade confirms the thesis, HUNT for additional entries at demand/supply.
   // These are EASIER entries: thesis already confirmed, just buying pullbacks to demand zone.
   //
   // Activation: when a Layer 1 signal fires -> enable hunt mode in that direction
   // Hunt zone for longs: at/below g_flipBot (the demand zone below the flip zone)
   // Hunt zone for shorts: at/above g_flipTop (the supply zone above the flip zone)
   // Deactivation: direction flip, invalidation, or wave reset

   // Activate hunt mode on Layer 1 entry
   if(longSignal && g_huntMode!=1){
      g_huntMode=1; g_huntActivatedBar=i;
      g_huntDemandHi=nz(g_flipBot,cl-atr); g_huntDemandLo=nz(g_point4OriginLow,g_huntDemandHi-atr*2.0);
   }
   if(shortSignal && g_huntMode!=-1){
      g_huntMode=-1; g_huntActivatedBar=i;
      g_huntDemandHi=nz(g_point4OriginHigh,g_flipTop+atr*2.0); g_huntDemandLo=nz(g_flipTop,cl+atr);
   }
   // Deactivate on invalidation or direction reset
   if(g_huntMode!=0 && (safeToReset||hardInvalid||(g_huntMode==1&&bullInvalid)||(g_huntMode==-1&&bearInvalid)))
      g_huntMode=0;

   // Layer 2 entry: price returns to demand/supply zone after the initial flip trade
   bool _huntLongZone = g_huntMode==1 && !naf(g_huntDemandHi) && cl<=g_huntDemandHi+atr*0.3 && cl>=g_huntDemandLo-atr*0.5;
   bool _huntShortZone = g_huntMode==-1 && !naf(g_huntDemandLo) && cl>=g_huntDemandLo-atr*0.3 && cl<=g_huntDemandHi+atr*0.5;
   // Relaxed conditions for continuation: hunt direction (thesis confirmed) + impulse/FU reaction + not locked
   bool _huntReactionLong  = bullImpulse || bullMicroImpulse || _fuConfirmLong || bullConvShift;
   bool _huntReactionShort = bearImpulse || bearMicroImpulse || _fuConfirmShort || bearConvShift;
   // Hunt uses g_huntMode direction (Layer 1 already confirmed thesis), NOT _macroDir
   // This allows anticipatory sells (H4 still bull) to continue hunting at supply
   // ALSO enforce flip context: hunt buys below flip, hunt sells above flip
   bool huntLongSignal  = showSignals && _huntLongZone && _huntReactionLong && _flipCtxAllowLong && g_huntMode==1 && !signalLocked && !withinLongLock && (i-g_huntActivatedBar)>5;
   bool huntShortSignal = showSignals && _huntShortZone && _huntReactionShort && _flipCtxAllowShort && g_huntMode==-1 && !signalLocked && !withinShortLock && (i-g_huntActivatedBar)>5;

   // Merge Layer 1 + Layer 2 signals
   if(huntLongSignal && !longSignal)  { longSignal=true; }
   if(huntShortSignal && !shortSignal){ shortSignal=true; }

   if(longSignal){ g_lastSignalBar=i; g_lastLongBar=i; g_engineArmed=false; }
   if(shortSignal){ g_lastSignalBar=i; g_lastShortBar=i; g_engineArmed=false; }
   gBarLong=longSignal; gBarShort=shortSignal; gBarLongPx=lo-atr*0.7; gBarShortPx=hi+atr*0.7;

   //==============================================================
   // SECTION 24 -- TRADE STATE
   //==============================================================
   // ???????????????????????????????????????????????????????????????????
   // RECURSIVE CURVE OWNERSHIP ARCHITECTURE -- Specification v9
   // 7 probabilistic engines. No binary states. Continuous maturity.
   // "Who owns price, how mature is the curve, how much geometry remains?"
   // ???????????????????????????????????????????????????????????????????

   // ??? ENGINE 1: HIERARCHICAL OWNERSHIP (HOE) ??????????????????????
   // Ownership is DISTRIBUTED across all TFs. Not one winner.
   // Each TF has a % of ownership based on phase?dominance?progress?hierarchy.
   double _hoePct[6]; double _hoeTotal=0;
   for(int _oi=0;_oi<6;_oi++){
      int _ph=cur_cv_phase[_oi]; int _d=cur_cv_dir[_oi];
      double _wp=cur_cv_wp[_oi]; double _dm=cur_cv_dom[_oi];
      double _phW = (_ph>=1&&_ph<=4)?1.0:(_ph==5||_ph==6)?0.9:(_ph>=8&&_ph<=11)?0.7:(_ph>=12)?0.8:(_ph==7)?0.3:0.1;
      double _tfW = (_oi==5?1.0:_oi==4?0.85:_oi==3?0.70:_oi==2?0.55:_oi==1?0.35:0.20);
      _hoePct[_oi] = _phW * fmax2(_dm,5.0)/100.0 * fmax2(_wp,5.0)/100.0 * _tfW * (_d!=0?1.0:0.01);
      _hoeTotal += _hoePct[_oi];
   }
   // Normalize to percentages
   if(_hoeTotal>0) for(int _oi=0;_oi<6;_oi++) _hoePct[_oi]=_hoePct[_oi]/_hoeTotal*100.0;
   // Owner = highest %
   int _hoeOwnerIdx=-1; double _hoeOwnerPct=0;
   for(int _oi=0;_oi<6;_oi++){ if(_hoePct[_oi]>_hoeOwnerPct){ _hoeOwnerPct=_hoePct[_oi]; _hoeOwnerIdx=_oi; } }
   int    _hoeDir = _hoeOwnerIdx>=0 ? cur_cv_dir[_hoeOwnerIdx] : 0;
   double _hoeDom = _hoeOwnerIdx>=0 ? cur_cv_dom[_hoeOwnerIdx] : 0;
   double _hoeWP  = _hoeOwnerIdx>=0 ? cur_cv_wp[_hoeOwnerIdx] : 0;
   double _hoeComp= _hoeOwnerIdx>=0 ? cur_cv_comp[_hoeOwnerIdx] : 0;

   // ??? ENGINE 2: OWNERSHIP TRANSFER (OTE) ??????????????????????????
   // Continuous transfer: old vs new. Not binary.
   double _oteOldPct = fmax2(0.0, 100.0-_hoeDom);
   double _oteNewPct = _hoeDom;
   // Transfer maturity: 0-100% (how complete is the handover)
   double _oteMaturity = _oteNewPct;  // 0=stable old, 50=contested, 100=complete transfer

   // ??? ENGINE 3: GEOMETRY ENGINE (GE) ??????????????????????????????
   // Estimates available curvature -- not just distance.
   // How much curve is physically possible before impact?
   double _geDistTarget=NA;
   // Distance to owner's destination
   if(_hoeDir==-1){
      for(int _ti=5;_ti>=0;_ti--){
         if(cur_cv_dir[_ti]==1 && !naf(cur_cv_flipTop[_ti]) && cur_cv_flipTop[_ti]<cl){
            _geDistTarget=MathAbs(cl-cur_cv_flipTop[_ti])/fmax2(atr,1e-10); break;
         }
      }
   } else if(_hoeDir==1){
      for(int _ti=5;_ti>=0;_ti--){
         if(cur_cv_dir[_ti]==-1 && !naf(cur_cv_flipBot[_ti]) && cur_cv_flipBot[_ti]>cl){
            _geDistTarget=MathAbs(cur_cv_flipBot[_ti]-cl)/fmax2(atr,1e-10); break;
         }
      }
   }
   if(naf(_geDistTarget)) _geDistTarget=5.0;
   // Geometry components
   double _geVelocity = MathAbs(velocity)/fmax2(atr*0.1,1e-10);
   double _geAccel = MathAbs(acceleration)/fmax2(atr*0.05,1e-10);
   double _geConvexWidth = fmax2(0.4, 2.0*(1.0-_hoeComp/100.0));  // ATR units per loop
   double _geCurvatureR = fmax2(0.5, _geDistTarget / fmax2(_geVelocity*0.5+1.0, 1.0));
   double _geApproachSpeed = fmin2(100.0, _geVelocity*30.0 + _geAccel*20.0);
   // Geometry capacity: how many loops can PHYSICALLY fit in the remaining space?
   // Large capacity = wide curve = many large loops possible
   // Small capacity = compressed or close = failure swing + immediate entry
   double _geCapacity = fmin2(100.0, _geDistTarget*15.0 * (1.0-_hoeComp/200.0) / fmax2(_geConvexWidth, 0.4));

   // ??? ENGINE 4: RECURSIVE FORECAST (RFE) -- PREDICTIVE ????????????
   // Forecasts future loops from GEOMETRY (not thresholds).
   // Inputs: distance + compression + velocity + convexity + curvature
   // Outputs: expectedLoops, failureSwingProb, immediateExecProb
   int    _rfeExpectedLoops = (int)fmin2(5.0, fmax2(0.0, MathRound(_geDistTarget/_geConvexWidth)));
   // Large loops need: low compression + large distance + slow approach
   double _rfeLargeProb = fmin2(100.0, fmax2(0.0, _geCapacity*0.5 * (1.0-_hoeComp/100.0) * (1.0-_geApproachSpeed/200.0)));
   // Failure swing: high compression + small distance + fast approach + high curvature
   double _rfeFailSwingProb = fmin2(100.0, fmax2(0.0,
      _hoeComp*0.35 +                                    // high compression -> failure swing
      (100.0-_geCapacity)*0.25 +                          // small remaining space -> failure swing
      _geApproachSpeed*0.20 +                             // fast approach -> failure swing
      fmin2(30.0, MathAbs(convSmooth)/fmax2(atr*convMult,1e-10)*10.0))); // high curvature -> failure swing
   // Immediate execution: when all geometry says "no room for more loops"
   double _rfeImmediateProb = fmin2(100.0, fmax2(0.0,
      _rfeFailSwingProb*0.40 +                            // failure swing likely = entry close
      _geApproachSpeed*0.20 +                             // approaching fast
      (_oteMaturity>60?25.0:_oteMaturity>40?15.0:0.0) +  // transfer advanced
      (_geDistTarget<2.0?20.0:_geDistTarget<4.0?10.0:0.0) + // very close to target
      (g_nearFlipzone?15.0:0.0)));                        // already at zone
   // Exhaustion probability: how likely the current curve is dying
   double _rfeExhaustProb = fmin2(100.0, fmax2(0.0,
      _hoeWP*0.40 +                                       // high maturity = exhausting
      (100.0-_hoeDom)*0.30 +                              // low dominance = losing control
      (_geApproachSpeed<20?20.0:0.0)));                    // velocity dying

   // ??? CURVE EXHAUSTION ENGINE (CEE) ???????????????????????????????
   // Transitions finish because curves exhaust, not because phases end.
   // Transfer completes when newCurveEnergy > oldCurveEnergy AND old exhausted.
   double _ceeOldEnergy = fmax2(0.0, 100.0 - _oteMaturity);  // old curve's remaining energy
   double _ceeNewEnergy = _oteMaturity;                        // new curve's growing energy
   double _ceeExhaustProgress = fmin2(100.0, _hoeWP*0.5 + (100.0-_ceeOldEnergy)*0.3 + _rfeExhaustProb*0.2);
   bool   _ceeTransferComplete = _ceeNewEnergy > _ceeOldEnergy && _ceeExhaustProgress >= 60.0;

   // ??? ENGINE 5: CURVE MATURITY (CME) ??????????????????????????????
   // Everything is probabilistic. No binary EntryActive.
   // Maturity of the current lifecycle position.
   double _cmeExpansionPct = fmin2(100.0, _hoeWP<40 ? _hoeWP*2.5 : 0.0);
   double _cmeTransitionPct = fmin2(100.0, (_hoeWP>=40&&_hoeWP<65) ? (_hoeWP-40.0)*4.0 : 0.0);
   double _cmeRetracementPct = fmin2(100.0, (_hoeWP>=55&&_hoeWP<80) ? (_hoeWP-55.0)*4.0 : 0.0);
   double _cmeInductionPct = fmin2(100.0, (_hoeWP>=70&&_hoeWP<90) ? (_hoeWP-70.0)*5.0 : 0.0);
   double _cmeLiquidationPct = fmin2(100.0, (_hoeWP>=80&&_hoeWP<95) ? (_hoeWP-80.0)*6.67 : 0.0);
   double _cmeTerminalPct = fmin2(100.0, _hoeWP>=85 ? (_hoeWP-85.0)*6.67 : 0.0);
   // Entry probability: continuous, from geometry + transfer + maturity
   double _cmeEntryProb = fmin2(100.0,
      _oteMaturity*0.30 +          // ownership transfer maturity
      _rfeImmediateProb*0.25 +     // recursion forecast says entry imminent
      _cmeTerminalPct*0.20 +       // lifecycle terminal maturity
      (g_nearFlipzone?15.0:0.0) +  // proximity to zone
      _geApproachSpeed*0.10);      // approach speed
   int _cmeCyclesLeft = _rfeExpectedLoops;
   // Execution state: continuous (not binary)
   int _cmeExecState = _cmeEntryProb>=90 ? 5 :   // EXHAUSTED/DONE
                        _cmeEntryProb>=75 ? 4 :   // ACTIVE
                        _cmeEntryProb>=55 ? 3 :   // IMMINENT
                        _cmeEntryProb>=35 ? 2 :   // PREPARING
                        _cmeEntryProb>=15 ? 1 : 0; // BUILDING / TOO_EARLY

   // ??? ENGINE 6: OWNER-DRIVEN DESTINATION (ODDE) + TARGET EXTENSION ?
   // Target = OWNER's demand/supply. NOT entry TF.
   // Escalates on ownership change: H4->D1->W1 (target extends automatically).
   double _ddeTarget=NA; int _ddeTargetTF=-1;
   if(_hoeDir==-1){
      // Bearish owner -> destination = demand below (bullish curve's flip below price)
      for(int _ti=5;_ti>=0;_ti--){
         if(cur_cv_dir[_ti]==1 && !naf(cur_cv_flipTop[_ti]) && cur_cv_flipTop[_ti]<cl){
            _ddeTarget=cur_cv_flipTop[_ti]; _ddeTargetTF=_ti; break;
         }
      }
      // Fallback: owner's origin (where the bearish wave started from)
      if(naf(_ddeTarget)){
         double _owOrig=(_hoeOwnerIdx>=0?cur_cv_origin[_hoeOwnerIdx]:NA);
         if(!naf(_owOrig)&&_owOrig<cl){ _ddeTarget=_owOrig; _ddeTargetTF=_hoeOwnerIdx; }
         // Last fallback: highest available TF target going DOWN
         else {
            double _h4t=MapVal(se240.t,se240.tgt,se240.n,ct);
            double _h1t=MapVal(se60.t,se60.tgt,se60.n,ct);
            if(!naf(_h4t)&&_h4t<cl){ _ddeTarget=_h4t; _ddeTargetTF=5; }
            else if(!naf(_h1t)&&_h1t<cl){ _ddeTarget=_h1t; _ddeTargetTF=4; }
            else if(!naf(se5_tgt)&&se5_tgt<cl){ _ddeTarget=se5_tgt; _ddeTargetTF=2; }
         }
      }
   } else if(_hoeDir==1){
      // Bullish owner -> destination = supply above (bearish curve's flip above price)
      for(int _ti=5;_ti>=0;_ti--){
         if(cur_cv_dir[_ti]==-1 && !naf(cur_cv_flipBot[_ti]) && cur_cv_flipBot[_ti]>cl){
            _ddeTarget=cur_cv_flipBot[_ti]; _ddeTargetTF=_ti; break;
         }
      }
      if(naf(_ddeTarget)){
         double _owExt=(_hoeOwnerIdx>=0?cur_cv_extreme[_hoeOwnerIdx]:NA);
         if(!naf(_owExt)&&_owExt>cl){ _ddeTarget=_owExt; _ddeTargetTF=_hoeOwnerIdx; }
         else {
            double _h4t=MapVal(se240.t,se240.tgt,se240.n,ct);
            double _h1t=MapVal(se60.t,se60.tgt,se60.n,ct);
            if(!naf(_h4t)&&_h4t>cl){ _ddeTarget=_h4t; _ddeTargetTF=5; }
            else if(!naf(_h1t)&&_h1t>cl){ _ddeTarget=_h1t; _ddeTargetTF=4; }
            else if(!naf(se5_tgt)&&se5_tgt>cl){ _ddeTarget=se5_tgt; _ddeTargetTF=2; }
         }
      }
   }
   // TARGET EXTENSION: if current target TF < owner TF, the target should be on the owner's level
   // This ensures H1 entry targeting H4 demand (not H1 demand)
   if(_ddeTargetTF>=0 && _hoeOwnerIdx>=0 && _ddeTargetTF<_hoeOwnerIdx){
      // Target is on a lower TF than the owner -- try to extend to owner's level
      if(_hoeDir==-1){
         double _owDest=cur_cv_origin[_hoeOwnerIdx];
         if(!naf(_owDest)&&_owDest<cl) _ddeTarget=_owDest;
      } else if(_hoeDir==1){
         double _owDest=cur_cv_extreme[_hoeOwnerIdx];
         if(!naf(_owDest)&&_owDest>cl) _ddeTarget=_owDest;
      }
   }

   // ??? ENGINE 7: EXECUTION PROBABILITY (EPE) -- CONTINUOUS ?????????
   // Entry fires when probability is high enough. Not binary.
   // entryProb = ownership ? maturity ? geometry ? destination ? recursion
   double _eceOwnership = _hoeOwnerPct;
   double _eceMaturity = _cmeEntryProb;
   double _eceGeometry = fmin2(100.0, 100.0-_geCapacity);  // low capacity = close to execution
   double _eceCompression = _hoeComp;
   double _eceDestination = naf(_ddeTarget)?20.0:fmin2(100.0, 100.0-_geDistTarget*10.0);
   double _eceRecursion = _rfeImmediateProb;
   // Combined execution probability
   double _eceEntryConf = fmin2(100.0,
      _eceOwnership*0.15 +
      _eceMaturity*0.25 +
      _eceGeometry*0.20 +
      _eceCompression*0.10 +
      _eceDestination*0.15 +
      _eceRecursion*0.15);
   // WIRE: store execution confidence as global so it reaches entry gates and display
   cur_entryProb = fmin2(100.0, fmax2(cur_entryProb, _eceEntryConf));  // upgrade if ECE is higher

   // ??? EXIT ENGINE ?????????????????????????????????????????????????
   // Never exit because entryTF target hit.
   // Exit when: destination reached OR ownership transfers OR curve exhausts.
   bool _destReached = !naf(_ddeTarget) && (g_tradeDir==1 ? cl>=_ddeTarget-atr*0.3 : g_tradeDir==-1 ? cl<=_ddeTarget+atr*0.3 : false);
   bool _ownershipAgainst = (g_tradeDir==1 && _hoeDir==-1 && _oteMaturity>=60.0) || (g_tradeDir==-1 && _hoeDir==1 && _oteMaturity>=60.0);
   bool _curveExhausted = _ceeTransferComplete && _rfeExhaustProb>=70.0;
   bool _domLost = _inl_dom_m5<25.0 && _inl_dom_m15<25.0 && _inl_dom_h1<25.0 && !_anyRungInReturn && !_anyRungInTerminal;
   bool exitCondition = _destReached || _ownershipAgainst || _curveExhausted ||
        (g_tradeDir==1&&bearBOS)||(g_tradeDir==-1&&bullBOS)||
        (g_tradeDir!=0&&safeToReset)||(g_tradeDir==1&&bullInvalid)||(g_tradeDir==-1&&bearInvalid)||
        (g_tradeDir!=0&&_domLost);

   // Hunt mode: on destination reached -> hunt at the reached zone
   if(_destReached && g_tradeDir==1 && g_huntMode!=-1){
      g_huntMode=-1; g_huntActivatedBar=i;
      g_huntDemandLo=nz(_ddeTarget,cl); g_huntDemandHi=g_huntDemandLo+atr*3.0;
   }
   if(_destReached && g_tradeDir==-1 && g_huntMode!=1){
      g_huntMode=1; g_huntActivatedBar=i;
      g_huntDemandHi=nz(_ddeTarget,cl); g_huntDemandLo=g_huntDemandHi-atr*3.0;
   }
   if(longSignal){ g_tradeDir=1; g_exitFiredBar=-1; }
   else if(shortSignal){ g_tradeDir=-1; g_exitFiredBar=-1; }
   else if(exitCondition&&g_tradeDir!=0){ g_exitFiredBar=i; g_tradeDir=0; }
   bool exitLatchActive=g_exitFiredBar>=0&&(i-g_exitFiredBar)<3;
   string directiveStr=longSignal?"BUY (ENTER LONG)":shortSignal?"SELL (ENTER SHORT)":exitLatchActive?"EXIT NOW":g_tradeDir==1?"HOLD LONG":g_tradeDir==-1?"HOLD SHORT":"NO TRADE / STAND DOWN";
   color directiveCol=longSignal?(color)0x88FF00:shortSignal?(color)0x4417FF:exitLatchActive?clrOrange:g_tradeDir==1?clrLime:g_tradeDir==-1?clrRed:clrGray;
   g_prevEnergy=energy;


   //==============================================================
   // DIE-2 -- FU ORDER BLOCK DETECTION + LIFECYCLE
   //==============================================================
   double fuRange=hi-lo, fuBody=MathAbs(cl-op), fuUpperWick=hi-fmax2(op,cl), fuLowerWick=fmin2(op,cl)-lo;
   double pO=(i>0)?o[i-1]:op, pH1=(i>0)?h[i-1]:hi, pL1=(i>0)?l[i-1]:lo, pC=(i>0)?c[i-1]:cl;
   double prevRange=pH1-pL1, prevBody=MathAbs(pC-pO), prevUpperWick=pH1-fmax2(pO,pC), prevLowerWick=fmin2(pO,pC)-pL1;
   double prevBodyRatio=prevRange>1e-10?prevBody/prevRange:0.0;
   double prevUpperWickRatio=prevRange>1e-10?prevUpperWick/prevRange:0.0;
   double prevLowerWickRatio=prevRange>1e-10?prevLowerWick/prevRange:0.0;
   bool bearGapLeave=op<pC-atr*0.05, bullGapLeave=op>pC+atr*0.05;
   bool liqLeftBear=!naf(pivH)||(pH1>nz(g_currSwingHigh,pH1)*0.998);
   bool liqLeftBull=!naf(pivL)||(pL1<nz(g_currSwingLow,pL1)*1.002);
   bool isBearFU_prev=prevRange>atr*0.5&&prevBodyRatio>=fuMinBodyRatio&&pC<pO&&prevUpperWickRatio>=fuMinWickRatio&&liqLeftBear&&bearGapLeave;
   bool isBullFU_prev=prevRange>atr*0.5&&prevBodyRatio>=fuMinBodyRatio&&pC>pO&&prevLowerWickRatio>=fuMinWickRatio&&liqLeftBull&&bullGapLeave;
   bool isBullFU=fuRange>atr*0.5&&fuBody/fmax2(fuRange,1e-10)>=fuMinBodyRatio&&cl>op&&fuLowerWick/fmax2(fuRange,1e-10)>=fuMinWickRatio&&((!fuRequireInZone)||(!naf(flipTop)&&!naf(flipBot)&&cl>=flipBot*0.98&&cl<=flipTop*1.02));
   bool isBearFU=fuRange>atr*0.5&&fuBody/fmax2(fuRange,1e-10)>=fuMinBodyRatio&&cl<op&&fuUpperWick/fmax2(fuRange,1e-10)>=fuMinWickRatio&&((!fuRequireInZone)||(!naf(flipTop)&&!naf(flipBot)&&cl>=flipBot*0.98&&cl<=flipTop*1.02));
   if(isBearFU_prev&&showFUBlocks) FuPush(fmax2(pO,pC),pL1,i-1,-1);
   if(isBullFU_prev&&showFUBlocks) FuPush(pH1,fmin2(pO,pC),i-1,1);
   if(isBullFU&&showFUBlocks) FuPush(hi,fmin2(op,cl),i,1);
   if(isBearFU&&showFUBlocks) FuPush(fmax2(op,cl),lo,i,-1);
   bool die_anyBullFUActive=false, die_anyBearFUActive=false; int die_activeFUCount=0;
   for(int fk=ArraySize(g_fu_top)-1;fk>=0;fk--){
      int age=i-g_fu_birthBar[fk];
      if(age>fuMaxBarsActive || g_fu_state[fk]=="Invalidated"){ FuRemove(fk); continue; }
      die_activeFUCount++;
      if(g_fu_dir[fk]==1) die_anyBullFUActive=true; else die_anyBearFUActive=true;
   }

   //==============================================================
   // FU WICK AUTHORITY (1A.8)
   //==============================================================
   double _fuwRange=fmax2(hi-lo,1e-10);
   double _fuwPriorHi=HighestPrior(h,i,fuwLookback), _fuwPriorLo=LowestPrior(l,i,fuwLookback);
   bool _fuwBearCand=!naf(_fuwPriorHi)&&hi>_fuwPriorHi&&cl<_fuwPriorHi&&(hi-fmax2(op,cl))/_fuwRange>=fuwMinWickFrac;
   bool _fuwBullCand=!naf(_fuwPriorLo)&&lo<_fuwPriorLo&&cl>_fuwPriorLo&&(fmin2(op,cl)-lo)/_fuwRange>=fuwMinWickFrac;
   if(_fuwBearCand){ g_fuw_dir=-1; g_fuw_tip=hi; g_fuw_bodyHigh=fmax2(op,cl); g_fuw_bodyLow=fmin2(op,cl); g_fuw_mid=g_fuw_bodyHigh+(g_fuw_tip-g_fuw_bodyHigh)*0.50; g_fuw_mid38=g_fuw_bodyHigh+(g_fuw_tip-g_fuw_bodyHigh)*0.38; g_fuw_mid62=g_fuw_bodyHigh+(g_fuw_tip-g_fuw_bodyHigh)*0.62; g_fuw_leftPool=_fuwPriorHi; g_fuw_bar=i; g_fuw_valid=false; g_fuw_strength=fmin2(100.0,(g_fuw_tip-g_fuw_bodyHigh)/fmax2(atr,1e-10)*40.0+40.0); }
   else if(_fuwBullCand){ g_fuw_dir=1; g_fuw_tip=lo; g_fuw_bodyHigh=fmax2(op,cl); g_fuw_bodyLow=fmin2(op,cl); g_fuw_mid=g_fuw_tip+(g_fuw_bodyLow-g_fuw_tip)*0.50; g_fuw_mid38=g_fuw_tip+(g_fuw_bodyLow-g_fuw_tip)*0.38; g_fuw_mid62=g_fuw_tip+(g_fuw_bodyLow-g_fuw_tip)*0.62; g_fuw_leftPool=_fuwPriorLo; g_fuw_bar=i; g_fuw_valid=false; g_fuw_strength=fmin2(100.0,(g_fuw_bodyLow-g_fuw_tip)/fmax2(atr,1e-10)*40.0+40.0); }
   if(!g_fuw_valid&&g_fuw_dir==-1&&!naf(g_fuw_bodyLow)&&i>g_fuw_bar&&cl<g_fuw_bodyLow) g_fuw_valid=true;
   if(!g_fuw_valid&&g_fuw_dir==1 &&!naf(g_fuw_bodyHigh)&&i>g_fuw_bar&&cl>g_fuw_bodyHigh) g_fuw_valid=true;
   double fuw_bandHi=(naf(g_fuw_mid38)||naf(g_fuw_mid62))?NA:fmax2(g_fuw_mid38,g_fuw_mid62);
   double fuw_bandLo=(naf(g_fuw_mid38)||naf(g_fuw_mid62))?NA:fmin2(g_fuw_mid38,g_fuw_mid62);
   double fuw_futureMagnet=g_fuw_valid?g_fuw_leftPool:NA;

   //==============================================================
   // 1A.9 -- MULTI-TF FU POOL MAGNETS
   //==============================================================
   int w_fuValid=MapValI(fpW.t,fpW.valid,fpW.n,ct),   d_fuValid=MapValI(fpD.t,fpD.valid,fpD.n,ct);
   int h4_fuValid=MapValI(fpH4.t,fpH4.valid,fpH4.n,ct),h1_fuValid=MapValI(fpH1.t,fpH1.valid,fpH1.n,ct);
   int m15_fuValid=MapValI(fpM15.t,fpM15.valid,fpM15.n,ct),m5_fuValid=MapValI(fpM5.t,fpM5.valid,fpM5.n,ct);
   double w_fuPool=MapVal(fpW.t,fpW.pool,fpW.n,ct),  w_fuMid=MapVal(fpW.t,fpW.mid,fpW.n,ct),  w_fuTip=MapVal(fpW.t,fpW.tip,fpW.n,ct),  w_fuScore=MapVal(fpW.t,fpW.score,fpW.n,ct);
   double d_fuPool=MapVal(fpD.t,fpD.pool,fpD.n,ct),  d_fuMid=MapVal(fpD.t,fpD.mid,fpD.n,ct),  d_fuTip=MapVal(fpD.t,fpD.tip,fpD.n,ct),  d_fuScore=MapVal(fpD.t,fpD.score,fpD.n,ct);
   double h4_fuPool=MapVal(fpH4.t,fpH4.pool,fpH4.n,ct),h4_fuMid=MapVal(fpH4.t,fpH4.mid,fpH4.n,ct),h4_fuTip=MapVal(fpH4.t,fpH4.tip,fpH4.n,ct),h4_fuScore=MapVal(fpH4.t,fpH4.score,fpH4.n,ct);
   double h1_fuPool=MapVal(fpH1.t,fpH1.pool,fpH1.n,ct),h1_fuMid=MapVal(fpH1.t,fpH1.mid,fpH1.n,ct),h1_fuTip=MapVal(fpH1.t,fpH1.tip,fpH1.n,ct),h1_fuScore=MapVal(fpH1.t,fpH1.score,fpH1.n,ct);
   double m15_fuPool=MapVal(fpM15.t,fpM15.pool,fpM15.n,ct),m15_fuMid=MapVal(fpM15.t,fpM15.mid,fpM15.n,ct),m15_fuTip=MapVal(fpM15.t,fpM15.tip,fpM15.n,ct),m15_fuScore=MapVal(fpM15.t,fpM15.score,fpM15.n,ct);
   double m5_fuTip=MapVal(fpM5.t,fpM5.tip,fpM5.n,ct),m5_fuScore=MapVal(fpM5.t,fpM5.score,fpM5.n,ct);
   int _fuActiveCnt=(w_fuValid==1?1:0)+(d_fuValid==1?1:0)+(h4_fuValid==1?1:0)+(h1_fuValid==1?1:0)+(m15_fuValid==1?1:0)+(m5_fuValid==1?1:0);
   double fu_recursiveAlign=(double)_fuActiveCnt/6.0*100.0;
   double fu_winTarget=NA,fu_winBand=NA; string fu_winSrc="-";
   if(w_fuValid==1&&!naf(w_fuPool)){ fu_winTarget=w_fuPool; fu_winSrc="W FU Left Pool"; fu_winBand=w_fuMid; }
   else if(d_fuValid==1&&!naf(d_fuPool)){ fu_winTarget=d_fuPool; fu_winSrc="D FU Left Pool"; fu_winBand=d_fuMid; }
   else if(h4_fuValid==1&&!naf(h4_fuPool)){ fu_winTarget=h4_fuPool; fu_winSrc="H4 FU Left Pool"; fu_winBand=h4_fuMid; }
   else if(h1_fuValid==1&&!naf(h1_fuPool)){ fu_winTarget=h1_fuPool; fu_winSrc="H1 FU Left Pool"; fu_winBand=h1_fuMid; }
   else if(m15_fuValid==1&&!naf(m15_fuPool)){ fu_winTarget=m15_fuPool; fu_winSrc="M15 FU Left Pool"; fu_winBand=m15_fuMid; }
   else if(g_fuw_valid&&!naf(fuw_futureMagnet)){ fu_winTarget=fuw_futureMagnet; fu_winSrc="FU Left Pool"; fu_winBand=g_fuw_mid; }

   //==============================================================
   // 1A.9B -- AFE (Alternating Flip Echo)
   //==============================================================
   if(g_fuw_valid&&(naf(g_afe_origin)||g_fuw_tip!=g_afe_origin)){
      g_afe_origin=g_fuw_tip; g_afe_originDir=g_fuw_dir; g_afe_upperFlip=g_fuw_mid;
      g_afe_lowerFlip=g_fuw_dir==-1?nz(g_prevSwingLow,g_fuw_bodyLow):nz(g_prevSwingHigh,g_fuw_bodyHigh);
      g_afe_step=1; g_afe_upperFlipRole="Destination"; g_afe_activeDest=g_fuw_mid; g_afe_target=NA; g_afe_selfReturnDone=false; g_afe_continuation=false;
   }
   if(g_afe_step>=1&&!naf(g_afe_origin)&&g_afe_originDir!=0){
      bool _afeBear=g_afe_originDir==-1;
      if(g_afe_step==1&&(_afeBear?cl<nz(g_fuw_bodyLow,g_afe_origin):cl>nz(g_fuw_bodyHigh,g_afe_origin))){ g_afe_step=2; g_afe_activeDest=g_afe_upperFlip; }
      if(g_afe_step==2&&!naf(g_afe_upperFlip)&&(_afeBear?hi>=g_afe_upperFlip:lo<=g_afe_upperFlip)){ g_afe_step=3; g_afe_selfReturnDone=true; g_afe_activeDest=g_afe_lowerFlip; }
      if(g_afe_step==3&&!naf(g_afe_lowerFlip)&&(_afeBear?lo<=g_afe_lowerFlip:hi>=g_afe_lowerFlip)){ g_afe_step=4; g_afe_activeDest=g_afe_origin; g_afe_target=g_afe_origin; g_afe_upperFlipRole="Liquidity"; }
      if(g_afe_step==4&&!naf(g_afe_origin)&&(_afeBear?hi>=g_afe_origin:lo<=g_afe_origin)){ g_afe_step=5; g_afe_continuation=true; }
   }

   //==============================================================
   // 1A.10 -- FU CONVERSATION (parent FU being sought)
   //==============================================================
   int conv_bias=displayWaveDir_M5!=0?displayWaveDir_M5:fractalStackDir;
   double conv_seekPx=NA,conv_seekSc=0.0; string conv_seekTf="-";
   if(conv_bias!=0){
      if(w_fuValid==1&&!naf(w_fuTip)&&(conv_bias==1?w_fuTip>cl:w_fuTip<cl)){ conv_seekPx=w_fuTip; conv_seekTf="W"; conv_seekSc=nz(w_fuScore); }
      else if(d_fuValid==1&&!naf(d_fuTip)&&(conv_bias==1?d_fuTip>cl:d_fuTip<cl)){ conv_seekPx=d_fuTip; conv_seekTf="D"; conv_seekSc=nz(d_fuScore); }
      else if(h4_fuValid==1&&!naf(h4_fuTip)&&(conv_bias==1?h4_fuTip>cl:h4_fuTip<cl)){ conv_seekPx=h4_fuTip; conv_seekTf="H4"; conv_seekSc=nz(h4_fuScore); }
      else if(h1_fuValid==1&&!naf(h1_fuTip)&&(conv_bias==1?h1_fuTip>cl:h1_fuTip<cl)){ conv_seekPx=h1_fuTip; conv_seekTf="H1"; conv_seekSc=nz(h1_fuScore); }
      else if(m15_fuValid==1&&!naf(m15_fuTip)&&(conv_bias==1?m15_fuTip>cl:m15_fuTip<cl)){ conv_seekPx=m15_fuTip; conv_seekTf="M15"; conv_seekSc=nz(m15_fuScore); }
      else if(m5_fuValid==1&&!naf(m5_fuTip)&&(conv_bias==1?m5_fuTip>cl:m5_fuTip<cl)){ conv_seekPx=m5_fuTip; conv_seekTf="M5"; conv_seekSc=nz(m5_fuScore); }
   }
   double conv_confidence=(conv_bias==0||naf(conv_seekPx))?0.0:fmin2(100.0,conv_seekSc*0.7+fu_recursiveAlign*0.3);

   //==============================================================
   // DIE-3/4 -- ENTRY SCORE + CONFLUENCE
   //==============================================================
   double die_entryScore=fmin2((nz(waveModelFit,50.0)*0.20)+(nz(modelConfidence,50.0)*0.20)+(htfAlign==direction&&direction!=0?20.0:htfAlign==0?10.0:0.0)+(nz(liqHeat,0.0)>50?15.0:nz(liqHeat,0.0)*0.30)+((die_anyBullFUActive&&direction==1)||(die_anyBearFUActive&&direction==-1)?15.0:0.0)+(flipzoneStagesComplete>=3?10.0:flipzoneStagesComplete*3.3),100.0);
   bool die_entryFUConfluence=((longSignal&&die_anyBullFUActive)||(shortSignal&&die_anyBearFUActive));
   string die_fuContrib=die_entryFUConfluence?"FU CONFIRMED":(((direction==1&&die_anyBullFUActive&&!longSignal)||(direction==-1&&die_anyBearFUActive&&!shortSignal))?"FU ASSISTED":"FU NOT PRESENT");

   //==============================================================
   // DASHBOARD INTEL -- dominance / fusion / cycles / geometry
   //==============================================================
   double _l1_expStrength=expScr_tf1, _l2_expStrength=expScr_tf2;
   string l1_dominantPhase=f_famSimple(f_phaseFamilyCode((int)nz(se15_ph)));
   double l1_modelFit=nz(se15_mf);
   g_l1_confidence=g_l1_confidence+0.4*(nz(se15_mf)-g_l1_confidence); g_l1_confidence=clamp(g_l1_confidence,10,100);
   string l2_dominantPhase=f_famSimple(f_phaseFamilyCode((int)nz(se60_ph)));
   double l2_modelFit=nz(se60_mf);
   g_l2_confidence=g_l2_confidence+0.4*(nz(se60_mf)-g_l2_confidence); g_l2_confidence=clamp(g_l2_confidence,10,100);
   string l3_dominantPhase=f_famMicro(f_phaseFamilyCode((int)nz(se3_ph)));
   double l3_confidence=clamp(nz(se3_mf),10,100);
   string l0_dominantPhase=ie1a_hypFamily; double l0_confidence=ie1a_phaseConfidence;
   int fam_l0=f_phaseFamilyCode((int)nz(se5_ph));
   double l0_dominance=fmin2(nz(se5_wp)*0.45+nz(se5_mf)*0.35+nz(se5_cm)*0.20,100.0);
   double l1_dominance=fmin2(_l1_expStrength*0.35+(expScr_tf1>60?25.0:expScr_tf1*0.40)+liqScr_tf1*0.20+l1_modelFit*0.20,100.0);
   double l2_dominance=fmin2(_l2_expStrength*0.35+(expScr_tf2>60?30.0:expScr_tf2*0.50)+liqScr_tf2*0.15+l2_modelFit*0.20,100.0);
   double l3_dominance=fmin2(nz(se3_mf)*0.60+nz(se3_wp)*0.40,100.0);
   string dominantWaveLevel=(l2_dominance>=l1_dominance&&l2_dominance>=l0_dominance&&l2_dominance>=l3_dominance)?"L2 HTF":(l1_dominance>=l0_dominance&&l1_dominance>=l3_dominance)?"L1 CHILD":(l0_dominance>=l3_dominance)?"L0 PRIMARY":"L3 MICRO";
   bool htfTrendIntact=l2_dominantPhase=="Expansion"&&g_l2_confidence>45.0;
   bool ltfReversalForming=((fam_l0==4||fam_l0==5)||(l3_dominantPhase=="M1 Transition Environment"||l3_dominantPhase=="M1 Liquidity"))&&!(g_liqg_active&&!(liqg_objArrival&&liqg_trueCHoCH));
   string fusionInterpretation=(htfTrendIntact&&!ltfReversalForming)?"HTF Intact - LTF Expansion Aligned":(htfTrendIntact&&ltfReversalForming)?"HTF Intact - LTF Reversal Forming":(!htfTrendIntact&&ltfReversalForming)?"HTF Weakening - LTF Reversal Confirming":(l2_dominantPhase=="Transition Environment"&&l1_dominantPhase=="Expansion")?"HTF Transition - ITF Counter-Bounce":(l2_dominantPhase=="Liquidity"&&(l1_dominantPhase=="Transition Environment"||fam_l0==5))?"HTF Liq Sweep - Entry Zone Forming":"Mixed - Await Alignment";
   double fusionConfidence=fmin2(g_l2_confidence*0.40+g_l1_confidence*0.30+l0_confidence*0.20+l3_confidence*0.10,100.0);
   double _cycleBaseProg=nz(waveProgress,0.0);
   double cycle1_completion=fmin2((g_entryCycle>=1?60.0:_cycleBaseProg*0.60)+(recursiveComplete&&g_entryCycle>=1?40.0:0.0),100.0);
   double cycle2_completion=fmin2((g_entryCycle>=2?60.0:g_entryCycle>=1?_cycleBaseProg*0.40:0.0)+(recursiveComplete&&g_entryCycle>=2?40.0:0.0),100.0);
   double cycle3_completion=fmin2((g_entryCycle>=3?60.0:g_entryCycle>=2?_cycleBaseProg*0.40:0.0)+(recursiveComplete&&g_entryCycle>=3?40.0:0.0),100.0);
   double cycle4_completion=fmin2((g_entryCycle>=4?60.0:g_entryCycle>=3?_cycleBaseProg*0.40:0.0)+(recursiveComplete&&g_entryCycle>=4?40.0:0.0),100.0);
   string activeCyclePhase=g_entryCycle==0?("Cycle 1 - "+l0_phaseCanon):("Entry Cycle "+IntegerToString(g_entryCycle)+" - "+l0_phaseCanon);
   double geoCapacityScore=fmin2((geoFullConvexityPossible?100.0:geoPartialConvexityPossible?60.0:25.0)*(!naf(flipzoneWidth)?fmax2(0.5,1.0-flipzoneWidth/fmax2(atr*4.0,1e-10)):0.5),100.0);
   string geoCapacityNarrative=geoFullConvexityPossible?"Full Conv - Complete wave expression":geoPartialConvexityPossible?"Partial Conv - Limited but tradeable":"Transition Only - Expect rapid transition";


   //==============================================================
   // SECTION 17/19 -- FUTURE RETURN ZONE ENGINE
   //==============================================================
   string frz_ownerLayer=dominantWaveLevel;
   bool frz_hasFU_gc=isBullFU_prev||isBearFU_prev;
   bool frz_hasFU_sb=isBullFU||isBearFU;
   bool frz_hasFU=frz_hasFU_gc||frz_hasFU_sb;
   bool frz_fuIsBull=isBullFU_prev||isBullFU;
   bool frz_fuIsBear=isBearFU_prev||isBearFU;
   bool frz_hasImbalance=displacement>dispThresh;
   bool frz_hasLiqClear=liqSweepBull||liqSweepBear||liqVacuum||(obs_LiquidityScore>55.0);
   bool frz_hasDisp=bullImpulse||bearImpulse;
   int frz_rawScore=(frz_hasFU?25:0)+(frz_hasImbalance?25:0)+(frz_hasLiqClear?25:0)+(frz_hasDisp?25:0);
   bool frz_liqResting=liqHeat>60&&!(liqSweepBull||liqSweepBear);
   bool frz_approved=!frz_liqResting;
   string frz_class=frz_rawScore>=76?"Exceptional":frz_rawScore>=51?"Strong":frz_rawScore>=26?"Moderate":"Weak";
   string frz_tier=frz_rawScore>=76?"T1":frz_rawScore>=51?"T2":(frz_rawScore>=26&&frz_hasFU)?"T3":(frz_rawScore>=26&&frz_hasImbalance)?"T4":"-";
   string frz_tierFull=frz_rawScore>=76?"Tier 1 ***":frz_rawScore>=51?"Tier 2 **":(frz_rawScore>=26&&frz_hasFU)?"Tier 3 *":(frz_rawScore>=26&&frz_hasImbalance)?"Tier 4":"-";
   string frz_compStr=(frz_hasFU&&frz_hasImbalance&&frz_hasLiqClear&&frz_hasDisp)?"FU+IMB+LS+DISP":(frz_hasFU&&frz_hasImbalance&&frz_hasLiqClear)?"FU+IMB+LS":(frz_hasFU&&frz_hasImbalance&&frz_hasDisp)?"FU+IMB+DISP":(frz_hasFU&&frz_hasImbalance)?"FU+IMB":(frz_hasFU&&frz_hasLiqClear)?"FU+LS":frz_hasFU?"FU":(frz_hasImbalance&&frz_hasLiqClear)?"IMB+LS":frz_hasImbalance?"IMB":"-";
   int _frz_spawnDir=(direction==1||frz_fuIsBull)&&!(direction==-1||frz_fuIsBear)?1:((direction==-1||frz_fuIsBear)&&!(direction==1||frz_fuIsBull)?-1:(direction!=0?direction:0));
   double _frz_zTop=_frz_spawnDir==1?fmax2(op,cl):hi;
   double _frz_zBot=_frz_spawnDir==1?lo:fmin2(op,cl);
   if(frz_hasFU_gc){ _frz_zTop=_frz_spawnDir==1?pH1:fmax2(pO,pC); _frz_zBot=_frz_spawnDir==1?fmin2(pO,pC):pL1; }
   if(_frz_zTop<=_frz_zBot){ _frz_zTop=fmax2(op,fmax2(cl,hi)); _frz_zBot=fmin2(op,fmin2(cl,lo)); }
   bool _frz_overlaps=false; int _frzExist=ArraySize(g_frz_top);
   for(int oi=0;oi<_frzExist;oi++){
      double ot=g_frz_top[oi],ob=g_frz_bot[oi];
      double ovHi=fmin2(_frz_zTop,ot),ovLo=fmax2(_frz_zBot,ob);
      double ov=fmax2(0.0,ovHi-ovLo); double thisRange=fmax2(_frz_zTop-_frz_zBot,1e-10);
      if(ov/thisRange>0.5){ _frz_overlaps=true; break; }
   }
   bool frz_spawn=showFRZ&&frz_approved&&frz_rawScore>=frz_minScore&&frz_rawScore>0&&(frz_hasFU||frz_hasImbalance)&&_frz_spawnDir!=0&&!_frz_overlaps;
   if(frz_spawn){
      g_frz_totalSpawned++;
      int s=ArraySize(g_frz_top);
      ArrayResize(g_frz_top,s+1);ArrayResize(g_frz_bot,s+1);ArrayResize(g_frz_bar,s+1);ArrayResize(g_frz_dir,s+1);
      ArrayResize(g_frz_score,s+1);ArrayResize(g_frz_class,s+1);ArrayResize(g_frz_tier,s+1);ArrayResize(g_frz_tierF,s+1);
      ArrayResize(g_frz_comp,s+1);ArrayResize(g_frz_owner,s+1);ArrayResize(g_frz_status,s+1);ArrayResize(g_frz_idx,s+1);
      g_frz_top[s]=_frz_zTop; g_frz_bot[s]=_frz_zBot; g_frz_bar[s]=i; g_frz_dir[s]=_frz_spawnDir; g_frz_score[s]=frz_rawScore;
      g_frz_class[s]=frz_class; g_frz_tier[s]=frz_tier; g_frz_tierF[s]=frz_tierFull; g_frz_comp[s]=frz_compStr;
      g_frz_owner[s]=frz_ownerLayer; g_frz_status[s]="Open"; g_frz_idx[s]=g_frz_totalSpawned;
   }
   //--- lifecycle ---
   for(int fi=ArraySize(g_frz_top)-1;fi>=0;fi--){
      double ft=g_frz_top[fi],fb=g_frz_bot[fi]; int fbb=g_frz_bar[fi],fd=g_frz_dir[fi]; string fst=g_frz_status[fi];
      int fage=i-fbb;
      bool terminal=(fst=="Mitigated"||fst=="Invalidated");
      if(!terminal){
         bool wickIn=lo<=ft&&hi>=fb;
         bool closeIn=cl>=fb&&cl<=ft;
         bool invalid=(fd==1&&cl<fb-atr*0.1)||(fd==-1&&cl>ft+atr*0.1);
         string ns=fst;
         if(closeIn) ns="Mitigated"; else if(invalid) ns="Invalidated"; else if(wickIn&&fst=="Open") ns="Partial";
         if(ns!=fst) g_frz_status[fi]=ns;
         fst=ns; terminal=(fst=="Mitigated"||fst=="Invalidated");
      }
      if(terminal||fage>=frz_maxBarsActive){ FrzRemove(fi); }
   }
   //--- ownership tally + best zone ---
   int frz_ownL0=0,frz_ownL1=0,frz_ownL2=0,frz_ownL3=0,frz_activeCount=0,frz_bullCount=0,frz_bearCount=0;
   int frz_bestScore=0; string frz_bestClass="-",frz_bestTier="-",frz_bestComp="-",frz_bestOwner="-",frz_bestStatus="-";
   for(int fk=0;fk<ArraySize(g_frz_score);fk++){
      string own=g_frz_owner[fk],st=g_frz_status[fk]; int sc=g_frz_score[fk],fd2=g_frz_dir[fk];
      bool live=(st=="Open"||st=="Partial");
      if(live){
         frz_activeCount++; if(fd2==1) frz_bullCount++; else frz_bearCount++;
         if(own=="L0 PRIMARY") frz_ownL0++; else if(own=="L1 CHILD") frz_ownL1++; else if(own=="L2 HTF") frz_ownL2++; else frz_ownL3++;
         if(sc>frz_bestScore){ frz_bestScore=sc; frz_bestClass=g_frz_class[fk]; frz_bestTier=g_frz_tierF[fk]; frz_bestComp=g_frz_comp[fk]; frz_bestOwner=own; frz_bestStatus=st; }
      }
   }

   //==============================================================
   // V72 DECISION ARCHITECTURE
   //==============================================================
   int dir3=MapValI(mdir3.t,mdir3.dir,mdir3.n,ct), dir4=MapValI(mdir4.t,mdir4.dir,mdir4.n,ct);
   //--- V72.1 best FRZ zone (open/partial highest) ---
   int v72BestIdx=-1,v72BestSc=-1;
   for(int q=0;q<ArraySize(g_frz_score);q++){ string st=g_frz_status[q]; if(st=="Open"||st=="Partial"){ if(g_frz_score[q]>v72BestSc){ v72BestSc=g_frz_score[q]; v72BestIdx=q; } } }
   double frz_bestZoneTop=v72BestIdx>=0?g_frz_top[v72BestIdx]:NA;
   double frz_bestZoneBot=v72BestIdx>=0?g_frz_bot[v72BestIdx]:NA;
   int    frz_bestZoneDir=v72BestIdx>=0?g_frz_dir[v72BestIdx]:0;
   string frz_bestZoneTier=v72BestIdx>=0?g_frz_tier[v72BestIdx]:"-";
   double frz_bestZoneMid=(!naf(frz_bestZoneTop)&&!naf(frz_bestZoneBot))?(frz_bestZoneTop+frz_bestZoneBot)/2.0:NA;
   double frz_distanceToZone=(frz_activeCount>0&&!naf(frz_bestZoneMid))?MathAbs(cl-frz_bestZoneMid)/fmax2(atr,1e-10):NA;
   bool frz_inProximity=frz_activeCount>0&&!naf(frz_distanceToZone)&&frz_distanceToZone<in_frzProximityATR;
   double frz_resolutionScore=re_resolutionState=="RESOLVED"?90.0:re_resolutionState=="PARTIALLY RESOLVED"?50.0+re_recursiveCompletionScore*0.40:20.0+ede_dissipationProgress*0.30;
   double frz_residualEnergy=fmax2(0.0,100.0-frz_resolutionScore);
   double frz_attractorWeight=frz_activeCount>0?fmin2(frz_residualEnergy*0.50+frz_bestScore*0.30+(frz_bestStatus=="Open"?20.0:frz_bestStatus=="Partial"?10.0:0.0),100.0):0.0;
   bool frz_attractorConvergence=frz_activeCount>0&&!naf(eae_primaryAttractorPrice)&&!naf(frz_bestZoneMid)&&MathAbs(eae_primaryAttractorPrice-frz_bestZoneMid)/fmax2(atr,1e-10)<in_frzConvergenceATR;
   //--- V72.2 RIE ---
   double rot_pressure=fmin2(obs_DecayScore*in_rieW_decay+obs_AbsorptionScore*in_rieW_absorb+(convexityScore>40?convexityScore*in_rieW_convex:0.0)+(obs_LiquidityScore>50?15.0:0.0),100.0);
   double rot_controlStability=fmin2(obs_ExpansionScore*in_rieW_stabExp+(efficiency>effThresh?30.0:efficiency>effThresh*0.7?15.0:0.0)+(ede_state<=2?30.0:ede_state<=3?15.0:0.0),100.0);
   double rot_transferProbability=fmin2(rot_pressure*in_rieW_press+(100.0-rot_controlStability)*in_rieW_stabInv+(re_resolutionState=="UNRESOLVED"?20.0:re_resolutionState=="PARTIALLY RESOLVED"?10.0:0.0),100.0);
   string rot_state=rot_transferProbability>=75?"TRANSFER_IMMINENT":rot_transferProbability>=50?"CONTESTED":rot_transferProbability>=25?"SOFTENING":"STABLE";
   //--- V72.3 MCE ---
   int mce_t1d=l1_dir,mce_t2d=l2_dir,mce_t3d=dir3,mce_t4d=dir4;
   int _mceAll=(mce_t1d==displayWaveDir_M5&&displayWaveDir_M5!=0?1:0)+(mce_t2d==displayWaveDir_M5&&displayWaveDir_M5!=0?1:0)+(mce_t3d==displayWaveDir_M5&&displayWaveDir_M5!=0?1:0)+(mce_t4d==displayWaveDir_M5&&displayWaveDir_M5!=0?1:0);
   int _mceHtf=(mce_t3d==displayWaveDir_M5&&displayWaveDir_M5!=0?1:0)+(mce_t4d==displayWaveDir_M5&&displayWaveDir_M5!=0?1:0);
   int _mceExec=(mce_t1d==displayWaveDir_M5&&displayWaveDir_M5!=0?1:0)+(mce_t2d==displayWaveDir_M5&&displayWaveDir_M5!=0?1:0);
   double mce_alignmentScore=displayWaveDir_M5==0?0.0:(double)_mceAll/4.0*100.0;
   double mce_htfAlignmentScore=displayWaveDir_M5==0?0.0:fmin2(((double)_mceHtf/2.0*100.0)*0.55+fractalCtxScore*0.45,100.0);
   double mce_execAlignmentScore=displayWaveDir_M5==0?0.0:(double)_mceExec/2.0*100.0;
   string mce_htfAlignmentSummary=(mce_htfAlignmentScore>=80&&displayWaveDir_M5==1)?"HTF Bullish Continuation":(mce_htfAlignmentScore>=80&&displayWaveDir_M5==-1)?"HTF Bearish Continuation":(mce_htfAlignmentScore>=60&&rot_transferProbability<40)?"HTF Trend Intact":(mce_htfAlignmentScore>=50&&rot_transferProbability>=60)?"HTF Rotation Developing":mce_htfAlignmentScore<40?"HTF Contested - No Clear Bias":"HTF Developing";
   string mce_execAlignmentSummary=(ie1a_currentPhase=="Demand Return"&&mce_execAlignmentScore>=60)?"Execution Aligned - Long Window":(ie1a_currentPhase=="Supply Return"&&mce_execAlignmentScore>=60)?"Execution Aligned - Short Window":mce_execAlignmentScore<40?"Execution Conflict - Wait":"Execution Developing";
   //--- V72.4 NE ---
   bool _nePhaseExpBull=ie1a_currentPhase=="Expansion"||ie1a_currentPhase=="New High";
   bool _nePhaseExpBear=ie1a_currentPhase=="Expansion"||ie1a_currentPhase=="New Low";
   bool _nePullback=ie1a_currentPhase=="Retracement"||ie1a_currentPhase=="Retracement Pre-Convexity"||ie1a_currentPhase=="Retracement Induction"||ie1a_currentPhase=="Retracement Liquidity";
   string ne_dominantNarrative=displayWaveDir_M5==0?"No Clear Narrative":(displayWaveDir_M5==1&&_nePhaseExpBull&&rot_transferProbability<40)?"Bullish Continuation":(displayWaveDir_M5==-1&&_nePhaseExpBear&&rot_transferProbability<40)?"Bearish Continuation":(displayWaveDir_M5==1&&(_nePullback||ie1a_currentPhase=="Demand Return"))?"Bullish Pullback":(displayWaveDir_M5==-1&&(_nePullback||ie1a_currentPhase=="Supply Return"))?"Bearish Pullback":(displayWaveDir_M5==1&&(rot_transferProbability>=55||ie1a_currentPhase=="Transition Environment"))?"Bullish Reversal Developing":(displayWaveDir_M5==-1&&(rot_transferProbability>=55||ie1a_currentPhase=="Transition Environment"))?"Bearish Reversal Developing":(displayWaveDir_M5==1?"Bullish Developing":displayWaveDir_M5==-1?"Bearish Developing":"No Clear Narrative");
   double ne_narrativeStrength=fmin2(mce_alignmentScore*0.40+rot_controlStability*0.30+(re_resolutionState=="RESOLVED"?30.0:re_resolutionState=="PARTIALLY RESOLVED"?15.0:0.0),100.0);
   //--- V72.5 INV ---
   double inv_bullOriginPrice=!naf(point4OriginLow)?point4OriginLow-atr*in_invOriginBuffer:NA;
   double inv_bearOriginPrice=!naf(point4OriginHigh)?point4OriginHigh+atr*in_invOriginBuffer:NA;
   double inv_demandFailPrice=(direction==1&&!naf(flipBot))?flipBot-atr*in_invZoneBuffer:NA;
   double inv_supplyFailPrice=(direction==-1&&!naf(flipTop))?flipTop+atr*in_invZoneBuffer:NA;
   double inv_activeStop=direction==1?nz(inv_demandFailPrice,inv_bullOriginPrice):direction==-1?nz(inv_supplyFailPrice,inv_bearOriginPrice):NA;
   bool inv_invalidated=!naf(inv_activeStop)&&(direction==1?cl<inv_activeStop:direction==-1?cl>inv_activeStop:false);
   double inv_riskInPts=!naf(inv_activeStop)?MathAbs(cl-inv_activeStop):NA;
   //--- V72.6 TE ---
   double eae_tertiaryAttractorPrice=direction==1?fmax2(nz(eae_primaryAttractorPrice,cl),nz(eae_secondaryAttractorPrice,cl))+atr*in_teTertiaryATR:direction==-1?fmin2(nz(eae_primaryAttractorPrice,cl),nz(eae_secondaryAttractorPrice,cl))-atr*in_teTertiaryATR:NA;
   double te_tp1=NA; int _teBestSc=-1;
   if(direction!=0) for(int j2=0;j2<ArraySize(g_frz_score);j2++){ string st2=g_frz_status[j2]; int fd3=g_frz_dir[j2]; if((st2=="Open"||st2=="Partial")&&fd3==direction){ double mid2=(g_frz_top[j2]+g_frz_bot[j2])/2.0; bool beyond=direction==1?mid2>cl:mid2<cl; if(beyond&&g_frz_score[j2]>_teBestSc){ _teBestSc=g_frz_score[j2]; te_tp1=mid2; } } }
   // FIX: te_tp2 uses DIRECTIONAL trade target, not EAE energy attractor
   // For longs: target is above (se5_tgt when bullish, or flipTop + extension)
   // For shorts: target is below (se5_tgt when bearish, or flipBot - extension)
   double _te_dirTarget = NA;
   if(direction==1){
      if(!naf(se5_tgt) && se5_tgt>cl) _te_dirTarget=se5_tgt;
      else if(!naf(flipTop)) _te_dirTarget=flipTop+atr*2.0;
   } else if(direction==-1){
      if(!naf(se5_tgt) && se5_tgt<cl) _te_dirTarget=se5_tgt;
      else if(!naf(flipBot)) _te_dirTarget=flipBot-atr*2.0;
   }
   bool te_tp2_valid=!naf(_te_dirTarget)&&(direction==1?_te_dirTarget>cl:direction==-1?_te_dirTarget<cl:false);
   double te_tp2=te_tp2_valid?_te_dirTarget:NA;
   bool te_tp3_valid=in_teTertiaryOn&&!naf(eae_tertiaryAttractorPrice)&&(direction==1?eae_tertiaryAttractorPrice>cl:direction==-1?eae_tertiaryAttractorPrice<cl:false);
   double te_tp3=te_tp3_valid?eae_tertiaryAttractorPrice:NA;
   double _teTp1eff=!naf(te_tp1)?te_tp1:te_tp2;   // FRZ first, then directional target
   double te_rr_tp1=(!naf(_teTp1eff)&&!naf(inv_riskInPts)&&inv_riskInPts>0)?MathAbs(_teTp1eff-cl)/inv_riskInPts:NA;
   bool te_rrGate=!naf(te_rr_tp1)&&te_rr_tp1>=in_rrMinimum;
   string te_expectedPath=(re_resolutionState=="RESOLVED"&&mce_execAlignmentScore>=70)?"Direct":(ie1a_currentPhase=="Demand Return"||ie1a_currentPhase=="Supply Return")?"Direct":rot_transferProbability>50?"Retracement First":re_resolutionState=="UNRESOLVED"?"Range Then Breakout":"Direct";
   //--- V72.7 TQE ---
   double erf_pureConfidence=fmin2(20.0+(re_resolutionState=="RESOLVED"?30.0:re_resolutionState=="PARTIALLY RESOLVED"?20.0:10.0)+eae_primaryAttractorScore*0.30,100.0);
   double frz_entryBonus=(frz_inProximity&&frz_bestZoneDir==direction)?15.0:0.0;
   double tqe_frzQuality=frz_activeCount>0?fmin2(frz_bestScore*0.50+(frz_bestZoneTier=="T1"?40.0:frz_bestZoneTier=="T2"?25.0:frz_bestZoneTier=="T3"?10.0:0.0)+(frz_bestStatus=="Open"?10.0:frz_bestStatus=="Partial"?5.0:0.0)+frz_entryBonus,100.0):0.0;
   double tqe_liqQuality=fmin2(obs_LiquidityScore*0.50+((liqSweepBull||liqSweepBear)?30.0:0.0)+(liqVacuum?20.0:0.0),100.0);
   double tqe_rawScore=ie1a_phaseConfidence*in_tqeW_ie1a+erf_pureConfidence*in_tqeW_erf+tqe_frzQuality*in_tqeW_frz+mce_htfAlignmentScore*in_tqeW_mce+re_recursiveCompletionScore*in_tqeW_re+tqe_liqQuality*in_tqeW_liq;
   string tqe_grade=tqe_rawScore>=in_tqeGradeA1?"A+":tqe_rawScore>=in_tqeGradeA?"A":tqe_rawScore>=in_tqeGradeB?"B":tqe_rawScore>=in_tqeGradeC?"C":"D";
   string tqe_riskLevel=(rot_transferProbability>65||re_resolutionState=="UNRESOLVED")?"HIGH":(rot_transferProbability>35||tqe_rawScore<60)?"MEDIUM":"LOW";
   //--- V72.8 DOE ---
   string doe_bias=(displayWaveDir_M5==1&&mce_htfAlignmentScore>=75&&rot_controlStability>=65)?"Strong Bullish":displayWaveDir_M5==1?"Bullish":(displayWaveDir_M5==-1&&mce_htfAlignmentScore>=75&&rot_controlStability>=65)?"Strong Bearish":displayWaveDir_M5==-1?"Bearish":"Neutral";
   string doe_action=inv_invalidated?"No Trade":(g_liqg_active&&!(liqg_objArrival&&liqg_trueCHoCH))?"Wait":!erf_entryGate?"Wait":!te_rrGate?"Wait":(direction==1&&nz(se5_wp)>=75.0)?"Long":(direction==-1&&nz(se5_wp)>=75.0)?"Short":"Wait";
   double doe_confidence=fmin2(modelConfidence*0.50+mce_alignmentScore*0.25+phaseConfidence*0.25,frz_attractorConvergence?in_doeCapConv:in_doeCapBase);
   string doe_tradeType=(ne_dominantNarrative=="Bullish Continuation"||ne_dominantNarrative=="Bearish Continuation")?"Continuation":(ne_dominantNarrative=="Bullish Pullback"||ne_dominantNarrative=="Bearish Pullback")?"Pullback":(ie1a_currentPhase=="New High"||ie1a_currentPhase=="New Low")?"Breakout":"Wait";
   double doe_entryMid=(frz_inProximity&&frz_bestZoneDir==direction&&!naf(frz_bestZoneMid))?frz_bestZoneMid:((ie1a_currentPhase=="Demand Return"||ie1a_currentPhase=="Supply Return")&&!naf(point4OriginHigh)&&!naf(point4OriginLow))?(point4OriginHigh+point4OriginLow)/2.0:cl;
   double doe_entryHigh=!naf(doe_entryMid)?doe_entryMid+atr*0.30:NA;
   double doe_entryLow=!naf(doe_entryMid)?doe_entryMid-atr*0.30:NA;
   string doe_entryTrigger=frz_inProximity?"Limit":(ie1a_currentPhase=="Demand Return"||ie1a_currentPhase=="Supply Return")?"LimitOnRetest":"Market";
   //--- V72.8b OPPORTUNITY ---
   double _opStruct=displayWaveDir_M5==0?0.0:(direction==displayWaveDir_M5?100.0:70.0);
   double _opLifecycle=(ie1a_currentPhase=="Demand Return"||ie1a_currentPhase=="Supply Return")?100.0:(ie1a_currentPhase=="Transition Environment"||_nePullback)?70.0:(ie1a_currentPhase=="New High"||ie1a_currentPhase=="New Low")?55.0:(ie1a_currentPhase=="Expansion"||ie1a_currentPhase=="Expansion Pre-Convexity"||ie1a_currentPhase=="Expansion Induction"||ie1a_currentPhase=="Expansion Liquidity")?45.0:ie1a_currentPhase=="Point 4 Origin"?25.0:0.0;
   double _opReturn=naf(frz_distanceToZone)?(frz_inProximity?100.0:0.0):fmax2(0.0,100.0-frz_distanceToZone*40.0);
   double _opDisplace=fmax2(re_recursiveCompletionScore,ede_dissipationProgress);
   double _opConfluence=(frz_attractorConvergence?50.0:0.0)+((frz_inProximity&&frz_bestZoneDir==displayWaveDir_M5)?50.0:0.0);
   double oppProgressRaw=_opStruct*0.25+_opLifecycle*0.15+rot_transferProbability*0.15+_opReturn*0.15+mce_htfAlignmentScore*0.10+_opDisplace*0.10+_opConfluence*0.10;
   bool oppVeto=displayWaveDir_M5==0||inv_invalidated;
   double oppProgress=oppVeto?0.0:oppProgressRaw;
   bool _opInZone=frz_inProximity&&frz_bestZoneDir==displayWaveDir_M5;
   string oppState=oppVeto?"STAND DOWN":(oppProgress>=95&&_opInZone)?"TRADE ACTIVE":oppProgress>=85?"PREPARE TO EXECUTE":oppProgress>=60?"OPPORTUNITY CONFIRMING":oppProgress>=20?"OPPORTUNITY FORMING":"STAND DOWN";
   string _cmdDirWord=displayWaveDir_M5==1?"Bullish":displayWaveDir_M5==-1?"Bearish":"Neutral";
   string cmd_narrative=displayWaveDir_M5==0?"No directional thesis":inv_invalidated?_cmdDirWord+" thesis invalidated":(ie1a_currentPhase=="Demand Return"||ie1a_currentPhase=="Supply Return")?_cmdDirWord+" return-to-zone - execution window":(rot_transferProbability>=55||ie1a_currentPhase=="Transition Environment")?_cmdDirWord+" reversal developing":(_nePullback||ie1a_currentPhase=="Retracement")?_cmdDirWord+" pullback in progress":(ie1a_currentPhase=="Expansion"||ie1a_currentPhase=="New High"||ie1a_currentPhase=="New Low")?_cmdDirWord+" continuation":_cmdDirWord+" developing";
   //--- registries ---
   V72Registries(i,direction,ie1a_currentPhase,re_recursiveCompletionScore,ede_expansionEnergy,ede_state,ede_liquidationBecomingDirectional,re_resolutionState);
   //--- traceability ---
   string trc_decisionSource="IE1A:"+ie1a_currentPhase+" | TQE:"+tqe_grade+" | NE:"+ne_dominantNarrative;
   string trc_confidenceBreakdown="IE1A:"+R0(ie1a_phaseConfidence)+" ERF:"+R0(erf_pureConfidence)+" FRZ:"+R0(tqe_frzQuality)+" MCE:"+R0(mce_htfAlignmentScore)+" RE:"+R0(re_recursiveCompletionScore)+" LIQ:"+R0(tqe_liqQuality);
   string trc_waveChain="Wave#"+IntegerToString(g_wr_activeId)+" (parent #"+IntegerToString(g_wr_activeParent)+", root #"+IntegerToString(g_wr_activeRoot)+")";
   //--- TPL destination ---
   double tpl_mainTarget=NA,tpl_confidence=0.0; string tpl_source="RANGEBOUND",tpl_winnerClass="Weak";
   TPLDestination(cl,atr,displayWaveDir_M5,fractalStackDir,liveHtfAlign,erf_tradeReadiness,
                  fu_winTarget,fu_winSrc,fu_winBand,fu_recursiveAlign,
                  frz_activeCount,frz_bestZoneMid,eae_primaryAttractorPrice,eae_primaryAttractorScore,
                  tpl_mainTarget,tpl_source,tpl_confidence,tpl_winnerClass);

   //==============================================================
   // STORE DISPLAY STATE (last bar drives rendering)
   //==============================================================
   if(isLast){
      cur_ie1aPhase=ie1a_currentPhase; cur_currentDisplayPhase=currentDisplayPhase; cur_hypFamily=ie1a_hypFamily;
      cur_dirM1=m1_dir; cur_dirM3=l3_dir; cur_dirM5=l0_dir; cur_dirM15=l1_dir; cur_dirH1=l2_dir; cur_dirH4=l4_dir;
      //--- MULTI-TIMEFRAME CURVE-OWNERSHIP + ENTRY SCANNER (F72) ------------
      //  Build context across ALL rungs FIRST, then qualify entries.
      //  Phase codes (this engine): 12 = Demand Return (LONG), 13 = Supply Return (SHORT).
      //  A Return is only an ENTRY CYCLE (not a first strike) once dominance has
      //  TRANSFERRED to the recursive wave (recDom high) - that is the build-vs-entry
      //  distinction. We also publish curve ownership / transition state / compression.
      {
         int    _phc[6]; double _inv[6]; int _wt[6]; string _tfn[6]; int _prev[6];
         double _dm[6]; double _cmp[6]; double _wpp[6]; double _rcc[6]; int _dr[6];
         _phc[0]=(int)nz(se1_ph);   _inv[0]=se1_inv;   _wt[0]=1; _tfn[0]="M1";  _prev[0]=gPrevPhM1;
         _phc[1]=(int)nz(se3_ph);   _inv[1]=se3_inv;   _wt[1]=2; _tfn[1]="M3";  _prev[1]=gPrevPhM3;
         _phc[2]=(int)nz(se5_ph);   _inv[2]=se5_inv;   _wt[2]=3; _tfn[2]="M5";  _prev[2]=gPrevPhM5;
         _phc[3]=(int)nz(se15_ph);  _inv[3]=se15_inv;  _wt[3]=4; _tfn[3]="M15"; _prev[3]=gPrevPhM15;
         _phc[4]=(int)nz(se60_ph);  _inv[4]=se60_inv;  _wt[4]=5; _tfn[4]="H1";  _prev[4]=gPrevPhH1;
         _phc[5]=(int)nz(se240_ph); _inv[5]=se240_inv; _wt[5]=6; _tfn[5]="H4";  _prev[5]=gPrevPhH4;
         _dm[0]=nz(MapVal(se1.t,se1.dom,se1.n,ct));    _cmp[0]=nz(MapVal(se1.t,se1.comp,se1.n,ct));    _wpp[0]=nz(MapVal(se1.t,se1.wp,se1.n,ct));    _rcc[0]=nz(MapVal(se1.t,se1.rec,se1.n,ct));    _dr[0]=m1_dir;
         _dm[1]=nz(MapVal(se3.t,se3.dom,se3.n,ct));    _cmp[1]=nz(MapVal(se3.t,se3.comp,se3.n,ct));    _wpp[1]=nz(MapVal(se3.t,se3.wp,se3.n,ct));    _rcc[1]=nz(MapVal(se3.t,se3.rec,se3.n,ct));    _dr[1]=l3_dir;
         _dm[2]=nz(MapVal(se5.t,se5.dom,se5.n,ct));    _cmp[2]=nz(MapVal(se5.t,se5.comp,se5.n,ct));    _wpp[2]=nz(MapVal(se5.t,se5.wp,se5.n,ct));    _rcc[2]=nz(MapVal(se5.t,se5.rec,se5.n,ct));    _dr[2]=l0_dir;
         _dm[3]=nz(MapVal(se15.t,se15.dom,se15.n,ct)); _cmp[3]=nz(MapVal(se15.t,se15.comp,se15.n,ct)); _wpp[3]=nz(MapVal(se15.t,se15.wp,se15.n,ct)); _rcc[3]=nz(MapVal(se15.t,se15.rec,se15.n,ct)); _dr[3]=l1_dir;
         _dm[4]=nz(MapVal(se60.t,se60.dom,se60.n,ct)); _cmp[4]=nz(MapVal(se60.t,se60.comp,se60.n,ct)); _wpp[4]=nz(MapVal(se60.t,se60.wp,se60.n,ct)); _rcc[4]=nz(MapVal(se60.t,se60.rec,se60.n,ct)); _dr[4]=l2_dir;
         _dm[5]=nz(MapVal(se240.t,se240.dom,se240.n,ct));_cmp[5]=nz(MapVal(se240.t,se240.comp,se240.n,ct));_wpp[5]=nz(MapVal(se240.t,se240.wp,se240.n,ct));_rcc[5]=nz(MapVal(se240.t,se240.rec,se240.n,ct));_dr[5]=l4_dir;

         //--- CURVE OWNER = highest rung that is mid-progress (wp in 10..90) = the live driver ---
         int _own=-1;
         for(int _r=5;_r>=0;_r--){ if(_wpp[_r]>10.0 && _wpp[_r]<90.0){ _own=_r; break; } }
         if(_own<0) _own=2;                          // fallback to M5 canonical
         cur_curveOwner=_tfn[_own]; cur_ownerDir=_dr[_own];
         cur_domTransfer=_dm[_own]; cur_recDepth=(int)_rcc[_own];
         double _oc=_cmp[_own];
         cur_compRegime=_oc>=80.0?"Extreme":_oc>=55.0?"High":_oc>=30.0?"Medium":"Low";
         int _opc=_phc[_own];
         //--- TRANSITION STATE: derived ENTIRELY from ownership engines (not SE phase) ---
         // Phase labels are downstream outputs. Ownership creates state.
         // Inputs: dominance, wave progress, LTF flip count, recursion, compression, zone proximity.
         double _owDomNow = _dm[_own];
         double _owWPnow = _wpp[_own];
         int _owDir = _dr[_own];
         int _ltfAgainstOwner = 0;
         for(int _ri=0;_ri<_own;_ri++) if(_dr[_ri]!=0 && _dr[_ri]!=_owDir) _ltfAgainstOwner++;
         double _owRecDepth = _rcc[_own];
         double _owComp = _cmp[_own];
         bool _owAtFlip = !naf(cur_cv_flipTop[_own]) && !naf(cur_cv_flipBot[_own]) &&
              cl<=cur_cv_flipTop[_own]*1.02 && cl>=cur_cv_flipBot[_own]*0.98;
         // Compute transition maturity from engines (NOT from phase code)
         double _owTransMat = _owDomNow*0.25 + _owWPnow*0.25 + (double)_ltfAgainstOwner*12.0 +
              _owRecDepth*10.0 + _owComp*0.10 + (_owAtFlip?15.0:0.0);
         // Recursion override: deep recursion + compressed + old dom collapsed = CANNOT be early
         if(_owRecDepth>=3 && _owComp>=50.0 && (100.0-_owDomNow)<50.0)
            _owTransMat = fmin2(90.0, _owTransMat+20.0);
         // State from maturity (ownership-driven, not phase-driven)
         // UNIFIED DEATH OVERRIDE: if Gate 7 already determined 2+ death signals,
         // cur_transState must reflect that -- no more BUILDING when curves are dying.
         if(cur_ownerDeathSignals >= 3)                         cur_transState="TRANSITION TERMINAL";
         else if(cur_ownerDeathSignals >= 2 || _owTransMat>=60.0 || (_owDomNow<30.0 && _ltfAgainstOwner>=2)) cur_transState="TRANSITION LATE";
         else if(_owTransMat>=35.0 || (_owDomNow<45.0 && _ltfAgainstOwner>=1)) cur_transState="TRANSITION MID";
         else if(_owWPnow<25.0 && _owDomNow>65.0)              cur_transState="BUILDING";
         else if(_owWPnow<50.0 && _owDomNow>50.0)              cur_transState="EXPANSION";
         else                                                    cur_transState="TRANSITION EARLY";
         // Zone-specific overrides (at flip = terminal context regardless of maturity)
         if(_owAtFlip && _owTransMat>=40.0)                     cur_transState="APPROACHING FLIP";
         if(_owAtFlip && _owTransMat>=60.0)                     cur_transState="TERMINAL";
         // Return detection: a rung is confirmed in Return phase
         if(_anyRungInReturn && _owDomNow>=40.0)                cur_transState="ENTRY (Return)";

         //--- ENTRY SCAN: a FRESH Return (12/13) on any rung is a candidate ---
         cur_mtfEntryDir=0; cur_mtfEntryFresh=false; cur_mtfEntryWt=0; cur_mtfEntryInv=NA; cur_mtfEntryTF="-"; cur_mtfEntryDom=0.0;
         int _bestWt=-1;
         for(int _r=0;_r<6;_r++){
            int _c=_phc[_r], _pc=_prev[_r];
            bool _isRet =(_c==12||_c==13);
            bool _wasRet=(_pc==12||_pc==13);
            if(_isRet && !_wasRet && _wt[_r]>_bestWt){            // fresh transition into Return
               _bestWt=_wt[_r];
               cur_mtfEntryDir=(_c==12?1:-1);                     // 12=Demand Return=LONG, 13=Supply Return=SHORT
               cur_mtfEntryFresh=true; cur_mtfEntryWt=_wt[_r];
               cur_mtfEntryInv=_inv[_r]; cur_mtfEntryTF=_tfn[_r];
               cur_mtfEntryDom=_dm[_r];
            }
         }
         //--- entry readiness: AUDIT FIX -- display now matches execution (cur_entryProb gates both) ---
         // _entryReadyGate uses (_execConfProxy + _budgetBonus + _recBonus >= 40%) + dom + terminal.
         // cur_entryReady mirrors that using cur_entryProb (which was upgraded by ECE in the v9 block).
         bool _erd_domOK = nz(MapVal(se5.t,se5.dom,se5.n,ct))>=50.0 || nz(MapVal(se15.t,se15.dom,se15.n,ct))>=75.0;
         bool _erd_phOK = _anyRungInReturn||_anyRungInTerminal;
         if(cur_mtfEntryFresh)                                  cur_entryReady=(cur_mtfEntryDom>=50.0?"Entry Active":"Pre-entry");
         else if(_erd_domOK && _erd_phOK && cur_entryProb>=70.0) cur_entryReady="Entry Active";
         else if(_erd_domOK && _erd_phOK && cur_entryProb>=45.0) cur_entryReady="Pre-entry";
         else if(cur_transState=="TRANSITION TERMINAL"||cur_transState=="TERMINAL"||cur_transState=="APPROACHING FLIP") cur_entryReady="Pre-entry";
         else if(cur_transState=="TRANSITION LATE"||cur_transState=="RETRACEMENT"||cur_transState=="ENTRY (Return)") cur_entryReady="Building";
         else if(cur_transState=="TRANSITION MID")              cur_entryReady="Early";
         else if(cur_transState=="TRANSITION EARLY")            cur_entryReady="Too Early";
         else                                                   cur_entryReady="Not Ready";

         //--- CURVE CAPACITY ENGINE: how much curve is left -> how many recursions fit -------
         //  Now consistent with ComputeSE's compression-derived recRequired.
         //  The state machine and capacity engine agree: high comp = more tiny cycles fit.
         double _destA = MapVal(se240.t,se240.tgt,se240.n,ct);
         if(naf(_destA)) _destA = MapVal(se60.t,se60.tgt,se60.n,ct);
         if(naf(_destA)) _destA = se5_tgt;
         double _atr2  = cur_atr>0?cur_atr:10*_Point;
         double _px    = c[i];
         cur_distFlipAtr = (!naf(_destA))? MathAbs(_px-_destA)/_atr2 : 5.0;
         double _wavelen = fmax2(0.4, 2.0*(1.0-_oc/100.0));          // loop size: low comp ~2 ATR, high comp ~0.4 ATR
         double _depthCap = (_oc>=80.0)?5.0:4.0;                     // F72: Extreme compression can fit a 5th micro-recursion
         // Use recRequired from the owner rung's SE output if available, else derive from wavelength
         double _ownerRecReq = nz(MapVal(se5.t,se5.recReq,se5.n,ct));
         if(_own==3) _ownerRecReq = nz(MapVal(se15.t,se15.recReq,se15.n,ct));
         else if(_own==4) _ownerRecReq = nz(MapVal(se60.t,se60.recReq,se60.n,ct));
         else if(_own==5) _ownerRecReq = nz(MapVal(se240.t,se240.recReq,se240.n,ct));
         int _capFromWavelen = (int)fmin2(_depthCap, fmax2(0.0, MathRound(cur_distFlipAtr/_wavelen)));
         cur_expRecDepth = (_ownerRecReq>0) ? (int)fmax2(0, _ownerRecReq - _rcc[_own]) : _capFromWavelen;
         cur_curveBudget = fmin2(100.0, cur_distFlipAtr*12.5);        // 8 ATR of room = "full" budget
         cur_transMaturity = cur_domTransfer;                         // dominance transfer % = how mature the transition is
         double _nearFlip = fmax2(0.0, 1.0 - cur_distFlipAtr/3.0);    // 1 at the flip, 0 beyond 3 ATR
         cur_entryProb = fmin2(100.0, cur_domTransfer*0.45 + _nearFlip*40.0 + (cur_mtfEntryFresh?15.0:0.0));

         gPrevPhM1=_phc[0]; gPrevPhM3=_phc[1]; gPrevPhM5=_phc[2];
         gPrevPhM15=_phc[3]; gPrevPhH1=_phc[4]; gPrevPhH4=_phc[5];
      }
      cur_l0phase=l0_phaseCanon; cur_l1phase=l1_phaseCanon; cur_l2phase=l2_phaseCanon; cur_l3phase=l3_phaseCanon; cur_l4phase=l4_phaseCanon;
      cur_phaseConfidence=phaseConfidence; cur_phaseIntegrity=phaseIntegrity; cur_phaseProgress=phaseProgress; cur_ie1aPhaseConf=ie1a_phaseConfidence;
      cur_fractalStackScore=fractalStackScore; cur_fractalCtxScore=fractalCtxScore; cur_fractalStackDir=fractalStackDir;
      cur_liveWaveDir=liveWaveDir; cur_liveHtfAlign=liveHtfAlign;
      cur_liqgActive=g_liqg_active; cur_liqgTitle=liqg_title; cur_liqgSub=liqg_subPhase; cur_liqgArr=liqg_arrTx; cur_liqgTarget=g_liqg_target; cur_liqgDistPct=liqg_distPct;
      cur_atr=atr; cur_velocity=velocity; cur_acceleration=acceleration; cur_efficiency=efficiency; cur_displacement=displacement;
      cur_velocityScore=velocityScore; cur_convexityScore=convexityScore; cur_expansionScore=expansionScore;
      cur_obsExp=obs_ExpansionScore; cur_obsDecay=obs_DecayScore; cur_obsCurv=obs_CurvatureScore; cur_obsAbs=obs_AbsorptionScore; cur_obsLiq=obs_LiquidityScore;
      cur_physicsConsensus=physicsConsensus; cur_physicsMax=physicsMax; cur_physicsDiff=physicsDiff; cur_volRegime=volRegime; cur_volRatio=volRatio;
      cur_bExp=d_expansionBelief; cur_bConv=d_convexityBelief; cur_bCreat=d_creationBelief; cur_bAbs=d_absorptionBelief; cur_bRetr=d_retracementBelief; cur_bDR=d_demandReturnBelief;
      cur_pxExp=expansionProximity; cur_pxConv=convexityProximity; cur_pxCreat=creationProximity; cur_pxAbs=absorptionProximity; cur_pxRetr=retracementProximity; cur_pxDR=demandReturnProximity;
      cur_primaryHyp=primaryHypothesis; cur_primaryHypConf=primaryHypothesisConf;
      cur_hypLE=hyp_LateExpansion_N; cur_hypEC=hyp_EarlyConvexity_N; cur_hypCF=hyp_CreationForming_N; cur_hypAA=hyp_AbsorptionActive_N; cur_hypRA=hyp_RetracementActive_N; cur_hypDR2=hyp_DemandReturn_N;
      cur_expectedNextPhase=expectedNextPhase; cur_expectedNextProb=expectedNextProb; cur_predReliability=predReliability; cur_predAcc10=predAcc10; cur_predAcc25=predAcc25;
      cur_modelConfidence=modelConfidence; cur_waveDeviation=waveDeviation; cur_deviationAlert=deviationAlert; cur_m1WarningScore=m1WarningScore; cur_m1Warning=m1Warning;
      cur_htfExpBelief=htf_ExpBelief; cur_htfConvBelief=htf_ConvBelief; cur_htfAbsBelief=htf_AbsBelief; cur_htfLiqBelief=htf_LiqBelief;
      cur_contProb=contProb; cur_finalProb=finalProb; cur_grade=grade; cur_gradeCol=gradeCol;
      cur_structBias=structBias; cur_htfAlign=htfAlign; cur_resonance=resonance;
      cur_liqHeat=liqHeat; cur_liqZone=liqZone; cur_liqVacuum=liqVacuum;
      cur_cycleCapacity=cycleCapacity; cur_geoCapNarr=geoCapacityNarrative; cur_geoCapScore=geoCapacityScore; cur_availableSpace=availableSpace; cur_zonePrecision=zonePrecision;
      cur_edeState=ede_state; cur_edeCleaning=ede_cleaningState; cur_edeDissProg=ede_dissipationProgress; cur_edeExpEnergy=ede_expansionEnergy;
      cur_reResolution=re_resolutionState; cur_reRecursiveCompletion=re_recursiveCompletionScore; cur_reResidual=re_residualEnergyScore; cur_reRevisit=re_revisitProbability;
      cur_eaeEnergyState=eae_energyState; cur_eaePrimaryLabel=eae_primaryAttractorLabel; cur_eaePrimaryPrice=eae_primaryAttractorPrice; cur_eaePrimaryScore=eae_primaryAttractorScore; cur_eaeSecondaryPrice=eae_secondaryAttractorPrice;
      cur_erfTradeReadiness=erf_tradeReadiness; cur_erfConfidence=erf_confidence; cur_erfEntryGate=erf_entryGate; cur_erfSuppressRotation=erf_suppressRotation;
      cur_expansionProbability=expansionProbability; cur_reversalProbability=reversalProbability; cur_tradeReadiness=tradeReadiness;
      cur_directiveStr=directiveStr; cur_directiveCol=directiveCol; cur_liveDirective=liveDirective;
      cur_buyProb=buyProb; cur_sellProb=sellProb; cur_netEdgeAdjusted=netEdgeAdjusted; cur_buyScore=buyScore; cur_sellScore=sellScore;
      cur_dieEntryScore=die_entryScore; cur_dieFuContrib=die_fuContrib; cur_longSignal=longSignal; cur_shortSignal=shortSignal; cur_tradeDir=g_tradeDir;
      cur_entryCycle=g_entryCycle; cur_waveDepth=g_waveDepth; cur_recursiveComplete=recursiveComplete;
      cur_cyc1=cycle1_completion; cur_cyc2=cycle2_completion; cur_cyc3=cycle3_completion; cur_cyc4=cycle4_completion; cur_activeCyclePhase=activeCyclePhase;
      cur_l0domPhase=l0_dominantPhase; cur_l1domPhase=l1_dominantPhase; cur_l2domPhase=l2_dominantPhase; cur_l3domPhase=l3_dominantPhase;
      cur_l0conf=l0_confidence; cur_l1conf=g_l1_confidence; cur_l2conf=g_l2_confidence; cur_l3conf=l3_confidence;
      cur_l0dom=l0_dominance; cur_l1dom=l1_dominance; cur_l2dom=l2_dominance; cur_l3dom=l3_dominance;
      cur_dominantWaveLevel=dominantWaveLevel; cur_fusionInterp=fusionInterpretation; cur_fusionConfidence=fusionConfidence;
      cur_frzActive=frz_activeCount; cur_frzBull=frz_bullCount; cur_frzBear=frz_bearCount; cur_frzBest=frz_bestScore;
      cur_frzL0=frz_ownL0; cur_frzL1=frz_ownL1; cur_frzL2=frz_ownL2; cur_frzL3=frz_ownL3;
      cur_frzBestClass=frz_bestClass; cur_frzBestTier=frz_bestTier; cur_frzBestComp=frz_bestComp; cur_frzBestOwner=frz_bestOwner; cur_frzBestStatus=frz_bestStatus;
      cur_frzBestTop=frz_bestZoneTop; cur_frzBestBot=frz_bestZoneBot; cur_frzBestMid=frz_bestZoneMid; cur_frzBestDir=frz_bestZoneDir;
      cur_anyBullFU=die_anyBullFUActive; cur_anyBearFU=die_anyBearFUActive; cur_fuWinTarget=fu_winTarget; cur_fuWinBand=fu_winBand; cur_fuRecursiveAlign=fu_recursiveAlign; cur_fuWinSrc=fu_winSrc;
      cur_convSeekPx=conv_seekPx; cur_convSeekSc=conv_seekSc; cur_convConfidence=conv_confidence; cur_convSeekTf=conv_seekTf;
      cur_rotState=rot_state; cur_rotTransfer=rot_transferProbability; cur_rotControl=rot_controlStability;
      cur_mceAlign=mce_alignmentScore; cur_mceHtfAlign=mce_htfAlignmentScore; cur_mceExecAlign=mce_execAlignmentScore; cur_mceHtfSummary=mce_htfAlignmentSummary; cur_mceExecSummary=mce_execAlignmentSummary;
      cur_neNarrative=ne_dominantNarrative; cur_neStrength=ne_narrativeStrength;
      cur_invActiveStop=inv_activeStop; cur_invRisk=inv_riskInPts; cur_invInvalidated=inv_invalidated;
      cur_teTp1=te_tp1; cur_teTp2=te_tp2; cur_teTp3=te_tp3; cur_teRR=te_rr_tp1; cur_teExpectedPath=te_expectedPath;
      cur_tqeGrade=tqe_grade; cur_tqeRisk=tqe_riskLevel; cur_tqeRaw=tqe_rawScore;
      cur_doeBias=doe_bias; cur_doeAction=doe_action; cur_doeTradeType=doe_tradeType; cur_doeTrigger=doe_entryTrigger; cur_doeConfidence=doe_confidence; cur_doeEntryMid=doe_entryMid; cur_doeEntryHigh=doe_entryHigh; cur_doeEntryLow=doe_entryLow;
      cur_oppProgress=oppProgress; cur_oppState=oppState; cur_cmdNarrative=cmd_narrative;
      cur_tplMainTarget=tpl_mainTarget; cur_tplConfidence=tpl_confidence; cur_tplSource=tpl_source; cur_tplWinnerClass=tpl_winnerClass;
      cur_trcDecision=trc_decisionSource; cur_trcConf=trc_confidenceBreakdown; cur_trcWaveChain=trc_waveChain;
   }
   g_prevDirection=direction; g_prevEntryCycle=g_entryCycle; g_prev_ede_state=ede_state; g_prev_LBD=ede_liquidationBecomingDirectional;
}


//==================================================================
// HELPER FUNCTIONS referenced by ProcessBar
//==================================================================
double f_idealSim(const double eO,const double dO,const double vO,const double cO,
                  const double eI,const double dI,const double vI,const double cI)
{
   double diff=MathPow(eO-eI,2)+MathPow(dO-dI,2)+MathPow(vO-vI,2)+MathPow(cO-cI,2);
   return(fmax2(0.0,100.0*(1.0-diff/4.0)));
}
double PredAcc(const int n)
{
   int cnt=MathMin(n,g_predTotalIdx); int sum=0; int start=MathMax(0,g_predTotalIdx-cnt);
   if(cnt>0) for(int q=start;q<g_predTotalIdx;q++) sum+=g_predOutcomes[q%100];
   return(cnt>0?(double)sum/(double)cnt*100.0:50.0);
}
double FindInducPrice(const double &h[],const double &l[],const int curIdx,const int anchorRefBar,
                      const double top,const double bot,const int lookback)
{
   if(anchorRefBar<0) return(NA);
   int maxI=MathMin(lookback,curIdx-anchorRefBar); if(maxI<1) return(NA);
   double best=NA,bestDist=NA;
   for(int ii=1;ii<=maxI;ii++){ int idx=curIdx-ii; if(idx<0) break;
      if(h[idx]<top && l[idx]>bot){ double dd=MathAbs((double)((curIdx-ii)-anchorRefBar)); if(naf(bestDist)||dd<bestDist){ bestDist=dd; best=(h[idx]+l[idx])/2.0; } } }
   return(best);
}
void FuPush(const double top,const double bot,const int birthBar,const int dir)
{
   int s=ArraySize(g_fu_top);
   ArrayResize(g_fu_top,s+1);ArrayResize(g_fu_bot,s+1);ArrayResize(g_fu_birthBar,s+1);ArrayResize(g_fu_dir,s+1);ArrayResize(g_fu_state,s+1);
   g_fu_top[s]=top; g_fu_bot[s]=bot; g_fu_birthBar[s]=birthBar; g_fu_dir[s]=dir; g_fu_state[s]="Fresh";
   if(ArraySize(g_fu_top)>300){ ArrayRemove(g_fu_top,0,1);ArrayRemove(g_fu_bot,0,1);ArrayRemove(g_fu_birthBar,0,1);ArrayRemove(g_fu_dir,0,1);ArrayRemove(g_fu_state,0,1); }
}
void FuRemove(const int idx)
{
   ArrayRemove(g_fu_top,idx,1);ArrayRemove(g_fu_bot,idx,1);ArrayRemove(g_fu_birthBar,idx,1);ArrayRemove(g_fu_dir,idx,1);ArrayRemove(g_fu_state,idx,1);
}
void FrzRemove(const int idx)
{
   ArrayRemove(g_frz_top,idx,1);ArrayRemove(g_frz_bot,idx,1);ArrayRemove(g_frz_bar,idx,1);ArrayRemove(g_frz_dir,idx,1);
   ArrayRemove(g_frz_score,idx,1);ArrayRemove(g_frz_class,idx,1);ArrayRemove(g_frz_tier,idx,1);ArrayRemove(g_frz_tierF,idx,1);
   ArrayRemove(g_frz_comp,idx,1);ArrayRemove(g_frz_owner,idx,1);ArrayRemove(g_frz_status,idx,1);ArrayRemove(g_frz_idx,idx,1);
}
int IndexOfInt(const int &arr[],const int v){ for(int q=0;q<ArraySize(arr);q++) if(arr[q]==v) return(q); return(-1); }

void V72Registries(const int i,const int direction,const string phase,const double reCompletion,
                    const double edeExpEnergy,const int edeState,const bool edeLBD,const string reState)
{
   int prevDir=g_prevDirection, prevCycle=g_prevEntryCycle;
   bool died=direction==0 && prevDir!=0;
   bool newRoot=(direction!=0&&prevDir==0)||(direction!=0&&prevDir!=0&&direction!=prevDir);
   bool newChild=direction!=0&&g_entryCycle>prevCycle&&!newRoot;
   if(died&&g_wr_activeId>0){ int di=IndexOfInt(g_wr_id,g_wr_activeId); if(di>=0){ g_wr_death[di]=i; g_wr_deathPh[di]=phase; g_wr_resScore[di]=reCompletion; } g_wr_activeId=0; g_wr_activeParent=0; g_wr_activeRoot=0; }
   if(newRoot||newChild){
      int newId=g_wr_nextId; g_wr_nextId++;
      int parent=newChild?g_wr_activeId:0;
      int root=(newChild&&g_wr_activeRoot>0)?g_wr_activeRoot:newId;
      int depth=newChild?MathMax(0,g_entryCycle):0;
      int s=ArraySize(g_wr_id);
      ArrayResize(g_wr_id,s+1);ArrayResize(g_wr_parent,s+1);ArrayResize(g_wr_root,s+1);ArrayResize(g_wr_birth,s+1);ArrayResize(g_wr_death,s+1);
      ArrayResize(g_wr_spawnPh,s+1);ArrayResize(g_wr_deathPh,s+1);ArrayResize(g_wr_peak,s+1);ArrayResize(g_wr_resScore,s+1);ArrayResize(g_wr_depth,s+1);
      g_wr_id[s]=newId; g_wr_parent[s]=parent; g_wr_root[s]=root; g_wr_birth[s]=i; g_wr_death[s]=-1;
      g_wr_spawnPh[s]=phase; g_wr_deathPh[s]=""; g_wr_peak[s]=edeExpEnergy; g_wr_resScore[s]=0.0; g_wr_depth[s]=depth;
      g_wr_activeId=newId; g_wr_activeParent=parent; g_wr_activeRoot=root;
      if(ArraySize(g_wr_id)>50){ ArrayRemove(g_wr_id,0,1);ArrayRemove(g_wr_parent,0,1);ArrayRemove(g_wr_root,0,1);ArrayRemove(g_wr_birth,0,1);ArrayRemove(g_wr_death,0,1);ArrayRemove(g_wr_spawnPh,0,1);ArrayRemove(g_wr_deathPh,0,1);ArrayRemove(g_wr_peak,0,1);ArrayRemove(g_wr_resScore,0,1);ArrayRemove(g_wr_depth,0,1); }
   }
   if(g_wr_activeId>0){ int ai=IndexOfInt(g_wr_id,g_wr_activeId); if(ai>=0&&edeExpEnergy>g_wr_peak[ai]) g_wr_peak[ai]=edeExpEnergy; }
   //--- delivery registry ---
   bool dwrSpawn=(edeState==4&&g_prev_ede_state!=4)||(edeLBD&&!g_prev_LBD);
   if(dwrSpawn){
      int did=g_dwr_nextId; g_dwr_nextId++;
      int s=ArraySize(g_dwr_id);
      ArrayResize(g_dwr_id,s+1);ArrayResize(g_dwr_root,s+1);ArrayResize(g_dwr_start,s+1);ArrayResize(g_dwr_end,s+1);ArrayResize(g_dwr_energy,s+1);ArrayResize(g_dwr_res,s+1);ArrayResize(g_dwr_cycle,s+1);
      g_dwr_id[s]=did; g_dwr_root[s]=g_wr_activeRoot; g_dwr_start[s]=i; g_dwr_end[s]=-1; g_dwr_energy[s]=edeExpEnergy; g_dwr_res[s]=reState; g_dwr_cycle[s]=g_entryCycle;
      g_dwr_activeId=did;
      if(ArraySize(g_dwr_id)>50){ ArrayRemove(g_dwr_id,0,1);ArrayRemove(g_dwr_root,0,1);ArrayRemove(g_dwr_start,0,1);ArrayRemove(g_dwr_end,0,1);ArrayRemove(g_dwr_energy,0,1);ArrayRemove(g_dwr_res,0,1);ArrayRemove(g_dwr_cycle,0,1); }
   }
   if(g_dwr_activeId>0){ int dwi=IndexOfInt(g_dwr_id,g_dwr_activeId); if(dwi>=0){ g_dwr_res[dwi]=reState; if(reState=="RESOLVED"&&g_dwr_end[dwi]==-1) g_dwr_end[dwi]=i; } }
}

string TplClass(const double s){ return(s>=92?"A+++":s>=85?"A++":s>=78?"A+":s>=68?"A":s>=55?"B":s>=40?"C":"Weak"); }

void TPLDestination(const double cl,const double atr,const int bias,const int fractalStackDir,const int liveHtfAlign,
                    const double erfReady,const double fuWinTarget,const string fuWinSrc,const double fuWinBand,const double fuRecursiveAlign,
                    const int frzActive,const double frzBestMid,const double eaePrice,const double eaeScore,
                    double &mainTarget,string &source,double &confidence,string &winnerClass)
{
   double bestScore=0.0,bestPrice=NA; string bestType="-";
   //--- FU candles ---
   if(bias!=0){
      for(int q=0;q<ArraySize(g_fu_top);q++){
         double fmid=(g_fu_top[q]+g_fu_bot[q])/2.0; int fdir=g_fu_dir[q]; string fst=g_fu_state[q];
         if(fst!="Invalidated"&&(bias==1?fmid>cl:fmid<cl)){
            double ov=(frzActive>0&&!naf(frzBestMid)&&MathAbs(fmid-frzBestMid)/fmax2(atr,1e-10)<1.0)?12.0:0.0;
            double b=(fst=="Fresh"||fst=="Active")?82.0:(fst=="Interacting")?76.0:70.0;
            double dpen=fmin2(MathAbs(cl-fmid)/fmax2(atr,1e-10)*2.0,22.0);
            double al=(fdir==fractalStackDir&&fractalStackDir!=0?8.0:0.0)+(fdir==liveHtfAlign&&liveHtfAlign!=0?6.0:0.0);
            double sc=fmin2(b+ov+al+erfReady*0.06-dpen,100.0);
            if(sc>bestScore){ bestScore=sc; bestPrice=fmid; bestType=ov>0?"FU + imbalance overlap":(fst=="Interacting")?"Residual FU":"FU candle"; }
         }
      }
   }
   //--- FU wick pool magnet + band ---
   if(bias!=0&&!naf(fuWinTarget)&&(bias==1?fuWinTarget>cl:fuWinTarget<cl)){
      double dpen=fmin2(MathAbs(cl-fuWinTarget)/fmax2(atr,1e-10)*1.5,14.0);
      double sc=fmin2(96.0+fuRecursiveAlign*0.04-dpen,100.0);
      if(sc>bestScore){ bestScore=sc; bestPrice=fuWinTarget; bestType=fuWinSrc+" (magnet)"; }
   }
   if(bias!=0&&!naf(fuWinBand)&&(bias==1?fuWinBand>cl:fuWinBand<cl)){
      if(90.0>bestScore){ bestScore=90.0; bestPrice=fuWinBand; bestType="FU induction band"; }
   }
   //--- FRZ zones ---
   if(bias!=0){
      for(int q=0;q<ArraySize(g_frz_top);q++){ string st=g_frz_status[q]; if(st=="Open"||st=="Partial"){
         double zmid=(g_frz_top[q]+g_frz_bot[q])/2.0; int zdir=g_frz_dir[q];
         if(bias==1?zmid>cl:zmid<cl){
            double dpen=fmin2(MathAbs(cl-zmid)/fmax2(atr,1e-10)*2.0,22.0);
            double al=(zdir==fractalStackDir&&fractalStackDir!=0?8.0:0.0)+(zdir==liveHtfAlign&&liveHtfAlign!=0?6.0:0.0);
            double sc=fmin2(g_frz_score[q]*0.85+al+erfReady*0.06-dpen,100.0);
            if(sc>bestScore){ bestScore=sc; bestPrice=zmid; bestType="FRZ "+g_frz_tier[q]; }
         } } }
   }
   //--- EAE attractor ---
   bool attOK=!naf(eaePrice)&&bias!=0&&(bias==1?eaePrice>cl:eaePrice<cl);
   if(attOK){ double sc=fmin2(eaeScore*0.45+(eaeScore>=70?6.0:0.0),100.0); if(sc>bestScore){ bestScore=sc; bestPrice=eaePrice; bestType="Flip / residual"; } }
   //--- resolve ---
   winnerClass=TplClass(bestScore); confidence=bestScore;
   if(bestScore>=55){ mainTarget=bestPrice; source=bestType; } else { mainTarget=NA; source="RANGEBOUND"; }
}


//==================================================================
// STATE RESET + HTF ENGINE BUILDER
//==================================================================
void ResetState()
{
   g_lastPivHigh=NA;g_prevPivHigh=NA;g_lastPivLow=NA;g_prevPivLow=NA;g_structBias=0;
   g_prevSwingHigh=NA;g_prevSwingLow=NA;g_currSwingHigh=NA;g_currSwingLow=NA;
   g_lastPivotPrice=NA;g_prevPivotPrice=NA;g_lastPivotBar=-1;g_prevPivotBar=-1;g_lastPivotDir=0;g_prevPivotDir=0;
   g_direction=0;g_flipTop=NA;g_flipBot=NA;g_obBirthBar=-1;g_barsInZone=0;g_contBar=-1;
   g_point4OriginHigh=NA;g_point4OriginLow=NA;g_point4OriginBar=-1;
   g_flipzoneInducPrice=NA;g_flipzoneInducLow=NA;g_flipzoneInducHigh=NA;
   g_inducExpOriginHigh=NA;g_inducExpExtremeLow=NA;g_inducExpOriginLow=NA;g_inducExpExtremeHigh=NA;
   g_inducRetrOriginHigh=NA;g_inducRetrExtremeLow=NA;g_inducRetrOriginLow=NA;g_inducRetrExtremeHigh=NA;
   g_inducZoneLow=NA;g_inducZoneHigh=NA;g_cycleHigh=NA;g_cycleLow=NA;
   g_waveGeneration=0;g_entryCycle=0;g_isRecursiveWave=false;g_waveDepth=0;g_lastSpawnDir=0;g_recursiveComplete=false;
   for(int k=0;k<4;k++){ g_cycObTop[k]=NA;g_cycObBot[k]=NA;g_cycFlipTop[k]=NA;g_cycFlipBot[k]=NA;g_cycP4High[k]=NA;g_cycP4Low[k]=NA;g_cycStartBar[k]=-1;g_cycDir[k]=0; }
   g_liqHeat=0;g_nearFlipzone=false;g_convexityMaturity=0;g_waveProgress=30;g_waveModelFit=50;
   g_expansionBelief=0;g_convexityBelief=0;g_creationBelief=0;g_absorptionBelief=0;g_retracementBelief=0;g_demandReturnBelief=0;g_modelConfidence=50;
   g_inductionEvidence=false;g_preConvEvidence=false;g_closeInside=false;g_m1AbsorptionEmer=false;g_m1ConvexityEmer=false;g_m1LiquidityEmer=false;
   ArrayInitialize(g_predOutcomes,0);g_predTotalIdx=0;g_lastExpectedPhase="Point 4 Origin";g_lastIE1APhase="Point 4 Origin";
   g_liqg_active=false;g_liqg_isRetr=false;g_liqg_dir=0;g_liqg_target=NA;g_liqg_initDist=NA;g_liqg_absorbUnlocked=false;
   g_recursiveJustFired=false;g_recursiveFiredBar=-1;
   ArrayFree(g_liqLevels);ArrayFree(g_liqWeights);ArrayFree(g_liqAges);ArrayFree(g_liqTypes);
   g_lastSignalBar=-1;g_lastLongBar=-1;g_lastShortBar=-1;g_engineArmed=true;
   g_tradeDir=0;g_exitFiredBar=-1;g_prevEnergy=0;g_prevDirection=0;g_prevEntryCycle=0;g_prev_ede_state=0;g_prev_LBD=false;
   g_huntMode=0;g_huntActivatedBar=-1;g_huntDemandHi=NA;g_huntDemandLo=NA;
   cur_ownerDeathSignals=0;
   ArrayFree(gMgTicket);ArrayFree(gMgInitSL);ArrayFree(gMgTP1);ArrayFree(gMgPartialDone);ArrayFree(gMgBEDone);ArrayFree(gMgDir);
   ArrayFree(gMgP1Done);ArrayFree(gMgP2Done);ArrayFree(gMgP3Done);ArrayFree(gMgP4Done);ArrayFree(gMgP5Done);
   ArrayFree(gMgTrailing);ArrayFree(gMgTrailSL);
   ArrayFree(gMgEntryTime);ArrayFree(gMgMFE);ArrayFree(gMgMAE);ArrayFree(gMgQProtMode);ArrayFree(gMgQExit50);
   ArrayFree(gMgIsDeathEntry);ArrayFree(gMgTradeType);
   ArrayFree(g_fu_top);ArrayFree(g_fu_bot);ArrayFree(g_fu_birthBar);ArrayFree(g_fu_dir);ArrayFree(g_fu_state);
   g_fuw_tip=NA;g_fuw_bodyHigh=NA;g_fuw_bodyLow=NA;g_fuw_mid=NA;g_fuw_mid38=NA;g_fuw_mid62=NA;g_fuw_dir=0;g_fuw_leftPool=NA;g_fuw_bar=-1;g_fuw_valid=false;g_fuw_strength=NA;
   g_afe_step=0;g_afe_origin=NA;g_afe_originDir=0;g_afe_upperFlip=NA;g_afe_lowerFlip=NA;g_afe_upperFlipRole="-";g_afe_activeDest=NA;g_afe_target=NA;g_afe_selfReturnDone=false;g_afe_continuation=false;
   ArrayFree(g_frz_top);ArrayFree(g_frz_bot);ArrayFree(g_frz_bar);ArrayFree(g_frz_dir);ArrayFree(g_frz_score);
   ArrayFree(g_frz_class);ArrayFree(g_frz_tier);ArrayFree(g_frz_tierF);ArrayFree(g_frz_comp);ArrayFree(g_frz_owner);ArrayFree(g_frz_status);ArrayFree(g_frz_idx);
   g_frz_totalSpawned=0;
   g_die_clusterCount=0;g_die_clusterStartBar=-1;g_die_clusterBestScore=0;g_die_inCluster=false;g_die_objMade=false;g_die_absUnlocked=false;
   g_l1_confidence=50;g_l2_confidence=50;
   ArrayFree(g_wr_id);ArrayFree(g_wr_parent);ArrayFree(g_wr_root);ArrayFree(g_wr_birth);ArrayFree(g_wr_death);ArrayFree(g_wr_depth);ArrayFree(g_wr_spawnPh);ArrayFree(g_wr_deathPh);ArrayFree(g_wr_peak);ArrayFree(g_wr_resScore);
   g_wr_nextId=1;g_wr_activeId=0;g_wr_activeParent=0;g_wr_activeRoot=0;
   ArrayFree(g_dwr_id);ArrayFree(g_dwr_root);ArrayFree(g_dwr_start);ArrayFree(g_dwr_end);ArrayFree(g_dwr_cycle);ArrayFree(g_dwr_energy);ArrayFree(g_dwr_res);
   g_dwr_nextId=1;g_dwr_activeId=0;
   g_htfBias1=0;g_htfBias2=0;
   ArrayFree(g_atrChart);ArrayFree(g_volChart);ArrayFree(g_velHist);
}

void BuildHTFEngines()
{
   ComputeSE(PERIOD_M1, HTF_BARS, pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen, se1);
   ComputeSE(PERIOD_M3, HTF_BARS, pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen, se3);
   ComputeSE(PERIOD_M5, HTF_BARS, pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen, se5);
   ComputeSE(PERIOD_M15,HTF_BARS, pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen, se15);
   ComputeSE(PERIOD_H1, HTF_BARS, pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen, se60);
   ComputeSE(PERIOD_H4, HTF_BARS, pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen, se240);
   ComputePhys(PERIOD_M5,HTF_BARS,atrLen,effLen,effThresh,dispThresh,convMult, phys5);
   ComputeBelief(tf1,HTF_BARS,atrLen,effThresh,dispThresh,convMult,obLookback, bel1);
   ComputeBelief(tf2,HTF_BARS,atrLen,effThresh,dispThresh,convMult,obLookback, bel2);
   ComputeM1(HTF_BARS,atrLen,effLen,effThresh,dispThresh,convMult, m1o);
   ComputeFUPool(PERIOD_W1, HTF_BARS, fuwMinWickFrac, fpW);
   ComputeFUPool(PERIOD_D1, HTF_BARS, fuwMinWickFrac, fpD);
   ComputeFUPool(PERIOD_H4, HTF_BARS, fuwMinWickFrac, fpH4);
   ComputeFUPool(PERIOD_H1, HTF_BARS, fuwMinWickFrac, fpH1);
   ComputeFUPool(PERIOD_M15,HTF_BARS, fuwMinWickFrac, fpM15);
   ComputeFUPool(PERIOD_M5, HTF_BARS, fuwMinWickFrac, fpM5);
   ComputeHtfDir(mce_tf3,HTF_BARS,atrLen,effThresh,dispThresh,obLookback, mdir3);
   ComputeHtfDir(mce_tf4,HTF_BARS,atrLen,effThresh,dispThresh,obLookback, mdir4);
}


//==================================================================
// UNIFIED DRIVER -- reprocess a window and set cur_* / gBar* outputs
// Caller should ResetState() first for a clean full recompute.
//==================================================================
void EngineRun(const int n,const datetime &time[],const double &open[],const double &high[],
               const double &low[],const double &close[],const double &volD[],const int startProcess)
{
   if(n<startProcess+3) return;
   BuildHTFEngines();
   int tgt=n-2;
   for(int i=startProcess;i<=tgt;i++)
      ProcessBar(i,open,high,low,close,time,volD,n,(i==tgt));
   g_lastProcessed=tgt;
}


//===================================================================
//  V60 CONTEXT (inlined from Letra37_Context.mqh)
//===================================================================
//+------------------------------------------------------------------+
//| Letra37_Context.mqh                                              |
//| Best-of-v60 ("F16 Raptor") FEATURE / CONTEXT layer for Letra,    |
//| ported on top of the shared Letra37 engine helpers.              |
//|                                                                  |
//| Ports the genuinely decision-improving parts of v60:             |
//|   - Adaptive timeframe ladder (climbs above H1, no collapse)     |
//|   - v60 14-phase structure engine (DIR-FIX + compression /       |
//|     recursive-transition / dominance-transfer)                   |
//|   - Fractal stack alignment                                      |
//|   - Invisible Network node engine (FU pools -> authority /       |
//|     netBias / pressure / primary attractor / FEZ / forward path) |
//|   - Time Intelligence Engine (MN/W/D/H4/H1 cycle stack)          |
//|   - Compact Energy/Resolution/Attractor read                     |
//|   (The Senseei meta-DECISION layer is intentionally NOT ported - |
//|    Letra's own decision stays the authority. This module only    |
//|    supplies FEATURES / CONTEXT consumed by Letra37_EA.)          |
//|   - F72 curve-life score ("is the trade alive?") for management  |
//+------------------------------------------------------------------+

//==================================================================
// SENSEEI INPUTS (distinct names; engine inputs are reused)
//==================================================================
input group "Letra37 - v60 Context (Network)"
input double sIn_wickFrac    = 0.30;   // FU spike: min wick / range
input int    sIn_lookback    = 3;      // FU spike: structure lookback
input int    sIn_authMin     = 45;     // Min node authority
input int    sIn_nodeMax     = 250;    // Max remembered nodes
input int    sIn_dormantBars = 120;    // Bars until dormant
input int    sIn_historyBars = 600;    // Bars until historical
input double sIn_tapAtr      = 0.40;   // FU extreme: tap band (xATR) for return-to-node entry
input int    sIn_tapMaxAge   = 60;     // FU extreme: max node age (bars) eligible for a tap entry

//==================================================================
// ADAPTIVE TIMEFRAME LADDER  (rung 3 = chart timeframe)
//==================================================================
ENUM_TIMEFRAMES SenLadder(const int rung)
{
   int s=PeriodSeconds(_Period);
   if(s<=3600){
      switch(rung){ case 1: return(PERIOD_M1); case 2: return(PERIOD_M3); case 3: return(_Period);
                    case 4: return(PERIOD_M15); case 5: return(PERIOD_H1); case 6: return(PERIOD_H4); }
   } else {
      switch(rung){ case 1: return(PERIOD_H1); case 2: return(PERIOD_H4); case 3: return(_Period);
                    case 4: return(PERIOD_D1); case 5: return(PERIOD_W1); case 6: return(PERIOD_MN1); }
   }
   return(_Period);
}
string SenTfLabel(const ENUM_TIMEFRAMES tf)
{
   switch(tf){ case PERIOD_M1: return("M1"); case PERIOD_M3: return("M3"); case PERIOD_M5: return("M5");
               case PERIOD_M15: return("M15"); case PERIOD_M30: return("M30"); case PERIOD_H1: return("H1");
               case PERIOD_H2: return("H2"); case PERIOD_H4: return("H4"); case PERIOD_H8: return("H8");
               case PERIOD_H12: return("H12"); case PERIOD_D1: return("D"); case PERIOD_W1: return("W");
               case PERIOD_MN1: return("MN"); }
   return(EnumToString(tf));
}

//==================================================================
// V60 STRUCTURE ENGINE -- 14-phase, DIR-FIX, compression/recursion
//==================================================================
struct SEV60
{
   datetime t[]; int n;
   double dir[], ph[], sh[], sl[], psh[], psl[], bos[], ch[];
   double p4h[], p4l[], inv[], tgt[], ft[], fb[], fs[], wp[], cm[], mf[];
   double comp[], rec[], dom[];
};

string f_phaseStrV60(const int c)
{
   switch(c){
      case 1:  return("Expansion");
      case 2:  return("Expansion Pre-Convexity");
      case 3:  return("Expansion Induction");
      case 4:  return("Expansion Liquidity");
      case 5:  return("New High");
      case 6:  return("New Low");
      case 7:  return("Transition");
      case 8:  return("Retracement");
      case 9:  return("HTF Flip Zone");
      case 10: return("Induction");
      case 11: return("Liquidation");
      case 12: return("Terminal Curve");
      case 13: return("Demand Return");
      case 14: return("Supply Return");
   }
   return("Point 4 Origin");
}

void ComputeSE_V60(const ENUM_TIMEFRAMES tfReq, const int bars,
                   const int pvLen, const int stLen, const int atrL,
                   const double effT, const double dispT, const double convM,
                   const double impM, const double chBuf, const int effL,
                   SEV60 &O)
{
   ENUM_TIMEFRAMES tf=SafeTF(tfReq);
   TFData d; if(!LoadTF(tf,bars,d) || d.n<2*pvLen+5){ O.n=0; return; }
   int n=d.n;
   double diff[]; ArrayResize(diff,n); diff[0]=0; for(int j=1;j<n;j++) diff[j]=d.c[j]-d.c[j-1];
   double vel[]; EMAarr(diff,vel,3);
   double acc[]; ArrayResize(acc,n); acc[0]=0; for(int j=1;j<n;j++) acc[j]=vel[j]-vel[j-1];
   double cvx[]; ArrayResize(cvx,n); cvx[0]=0; for(int j=1;j<n;j++) cvx[j]=acc[j]-acc[j-1];
   double csm[]; EMAarr(cvx,csm,3);
   double atr[]; ATRarr(d.h,d.l,d.c,atr,atrL);
   double phA[]; PivotHigh(d.h,phA,pvLen);
   double plA[]; PivotLow(d.l,plA,pvLen);

   O.n=n; ArrayResize(O.t,n);
   ArrayResize(O.dir,n);ArrayResize(O.ph,n);ArrayResize(O.sh,n);ArrayResize(O.sl,n);ArrayResize(O.psh,n);ArrayResize(O.psl,n);
   ArrayResize(O.bos,n);ArrayResize(O.ch,n);ArrayResize(O.p4h,n);ArrayResize(O.p4l,n);ArrayResize(O.inv,n);ArrayResize(O.tgt,n);
   ArrayResize(O.ft,n);ArrayResize(O.fb,n);ArrayResize(O.fs,n);ArrayResize(O.wp,n);ArrayResize(O.cm,n);ArrayResize(O.mf,n);
   ArrayResize(O.comp,n);ArrayResize(O.rec,n);ArrayResize(O.dom,n);

   double curSH=NA,curSL=NA,prSH=NA,prSL=NA;
   double lastP=NA,prevP=NA; int lastD=0,prevD=0;
   int    dir=0; double ftv=NA,fbv=NA,p4h=NA,p4l=NA,inv=NA,tgt=NA,cycH=NA,cycL=NA;
   bool   bos1=false,bos2=false; double protSw=NA,protSw2=NA,indOrig=NA,indExt=NA; bool indBrk=false;
   int    lastDirSeen=0; int recBrk=0; bool recArm=true; int pst=0;

   for(int j=0;j<n;j++){
      O.t[j]=d.t[j];
      double cl=d.c[j],op=d.o[j],hi=d.h[j],lo=d.l[j],A=atr[j];
      double velP=(j>0)?vel[j-1]:0, accP=(j>0)?acc[j-1]:0;
      double mv=(j>=effL)?MathAbs(cl-d.c[j-effL]):0.0;
      double ps=SumAbsDiff(d.c,j,effL);
      double eff=(ps>0)?mv/ps:0.0;
      double disp=(hi-lo)/fmax2(A,1e-10);
      bool bullImp=eff>effT && vel[j]>velP && acc[j]>0 && cl>op && disp>dispT;
      bool bearImp=eff>effT && vel[j]<velP && acc[j]<0 && cl<op && disp>dispT;
      bool bullDec=MathAbs(acc[j])<MathAbs(accP)*0.8 && vel[j]>0;
      bool bearDec=MathAbs(acc[j])<MathAbs(accP)*0.8 && vel[j]<0;
      double pH=phA[j], pL=plA[j];
      if(!naf(pH)){ prSH=naf(curSH)?pH:curSH; curSH=pH; }
      if(!naf(pL)){ prSL=naf(curSL)?pL:curSL; curSL=pL; }
      double eP=NA; int eD=0;
      if(!naf(pH)){ eP=pH; eD=1; } else if(!naf(pL)){ eP=pL; eD=-1; }
      if(eD!=0){ prevP=lastP; prevD=lastD; lastP=eP; lastD=eD; }
      bool bullBOS=!naf(prSH)&&cl>prSH;
      bool bearBOS=!naf(prSL)&&cl<prSL;
      bool bullCH =!naf(prSH)&&cl>prSH+A*chBuf;
      bool bearCH =!naf(prSL)&&cl<prSL-A*chBuf;
      bool eLong =!naf(pH)&&prevD==-1&&(pH-prevP)>A*impM;
      bool eShort=!naf(pL)&&prevD==1 &&(prevP-pL)>A*impM;
      bool hasCtx=dir!=0&&!naf(ftv);
      bool flipDn=dir==1 && bearCH;
      bool flipUp=dir==-1&& bullCH;
      bool isRev=(eLong&&dir==-1)||(eShort&&dir==1)||flipUp||flipDn;
      bool spawn=(eLong||eShort||flipUp||flipDn)&&(!hasCtx||isRev);
      if(spawn){
         int nd=eLong?1:eShort?-1:flipUp?1:-1;
         double _hi=fmax2(lastP,prevP), _lo=fmin2(lastP,prevP);   // DIR-FIX
         ftv=_hi; fbv=_lo; p4h=_hi; p4l=_lo; cycH=hi; cycL=lo; dir=nd;
         inv = nd==1?_lo:_hi;                                     // protective extreme
         double rng=(!naf(prSH)&&!naf(prSL))?MathAbs(prSH-prSL):A*5.0;
         tgt = nd==1?nz(ftv,cl)+rng:nz(fbv,cl)-rng;
      }
      if(dir==1)  cycH=naf(cycH)?hi:fmax2(cycH,hi);
      if(dir==-1) cycL=naf(cycL)?lo:fmin2(cycL,lo);
      int bosOut=bullBOS?1:bearBOS?-1:0;
      int chOut =bullCH?1:bearCH?-1:0;
      bool reset=(dir!=lastDirSeen); lastDirSeen=dir;
      if(reset){ bos1=false; bos2=false; protSw=NA; protSw2=NA; indOrig=NA; indExt=NA; indBrk=false; }
      if(dir==1 && !naf(pL)){ protSw2=protSw; protSw=pL; }
      if(dir==-1 && !naf(pH)){ protSw2=protSw; protSw=pH; }
      bool oppBOS=(dir==1&&!naf(protSw)&&cl<protSw)||(dir==-1&&!naf(protSw)&&cl>protSw);
      if(!bos1 && oppBOS){ bos1=true; indOrig=dir==1?nz(cycH,hi):nz(cycL,lo); }
      if(bos1 && !bos2 && oppBOS && !naf(protSw2) && (dir==1?cl<protSw2:cl>protSw2)) bos2=true;
      if(bos1 && dir==1)  indExt=naf(indExt)?cl:fmin2(indExt,cl);
      if(bos1 && dir==-1) indExt=naf(indExt)?cl:fmax2(indExt,cl);
      if(bos2 && !naf(indOrig)){ if(dir==1&&cl>indOrig) indBrk=true; if(dir==-1&&cl<indOrig) indBrk=true; }
      double convScore=fmin2(MathAbs(csm[j])/fmax2(A*convM,1e-10)*50.0,100.0);
      double expScore =fmin2(eff/fmax2(effT,1e-10)*50.0+disp/fmax2(dispT,1e-10)*50.0,100.0);
      double absScore =(eff<effT*0.7 && MathAbs(vel[j])<MathAbs(velP)*0.6)?60.0+convScore*0.4:convScore*0.3;
      bool momExpStrong=eff>effT*0.75 && (dir==1?vel[j]>0:vel[j]<0);
      bool momDecaying =dir==1?bullDec:bearDec;
      bool momCounter  =dir==1?bearImp:bullImp;
      bool momExhaust  =eff<effT*0.65 && absScore>40.0;
      bool physConvexDevel=convScore>35.0;
      bool physTransfer   =convScore>48.0 || absScore>40.0;
      bool physCapacityLow=absScore>45.0 || eff<effT*0.6;
      int wdir = !naf(inv)?(cl>inv?1:(cl<inv?-1:dir)):dir;
      bool atFlip=!naf(ftv)&&!naf(fbv)&&cl<=ftv&&cl>=fbv;
      bool expanding=momExpStrong||eLong||eShort||(wdir==1?bullImp:bearImp);
      bool atExtreme=wdir==1?hi>=nz(cycH,hi):(wdir==-1?lo<=nz(cycL,lo):false);
      double extr=wdir==1?nz(cycH,cl):nz(cycL,cl);
      bool extended=!naf(inv)&&MathAbs(extr-inv)>A*1.5;
      double fzMid=(!naf(ftv)&&!naf(fbv))?(ftv+fbv)/2.0:NA;
      double retrFrac=(!naf(fzMid)&&MathAbs(extr-fzMid)>1e-10)?MathAbs(extr-cl)/MathAbs(extr-fzMid):0.0;
      double compIdx=fmin2(100.0,fmax2(0.0,(1.0-fmin2(disp/fmax2(dispT,1e-10),1.0))*60.0+(1.0-fmin2(eff/fmax2(effT,1e-10),1.0))*40.0));
      bool phase2CH=(dir==1&&bearCH)||(dir==-1&&bullCH);
      if(reset||(atExtreme&&extended)){ recBrk=0; recArm=true; }
      if((dir==1&&!naf(pH))||(dir==-1&&!naf(pL))) recArm=true;
      if((phase2CH||oppBOS)&&recArm&&!atExtreme){ recBrk++; recArm=false; }
      //--- SPEC-CORRECT compression -> recursion mapping (V60 context engine) ---
      int recRequired = compIdx>=80 ? 5 : compIdx>=55 ? 4 : compIdx>=30 ? 3 : 1;
      double recDom=fmin2(100.0,fmax2(recBrk*(30.0-compIdx*0.15),retrFrac*80.0));
      bool energyExhausted = momExhaust || (eff<effT*0.6 && MathAbs(vel[j])<MathAbs(velP)*0.5);
      bool transferDone = recDom>=50.0 && (recBrk>=recRequired) && (energyExhausted || recDom>=75.0);
      if(reset) pst=0;
      if(dir!=0 && !reset){
         if(pst==0 && expanding) pst=1;
         if(pst==1 && !atExtreme && momDecaying && physConvexDevel) pst=2;
         if(pst==2 && !atExtreme && momCounter && physTransfer) pst=3;
         if(pst==3 && !atExtreme && (bos1||bos2||indBrk) && physTransfer) pst=4;
         if(pst>=1 && pst<=7 && atExtreme && extended) pst=5;
         if(pst==5 && !atExtreme && (recBrk>=1||momExhaust)) pst=7;
         // Transition stays in pst==7 until compression-required recursions complete
         if(pst==7 && transferDone) pst=8;
         if(pst==8 && atFlip) pst=9;
         if(pst==9 && ((dir==1&&bullImp)||(dir==-1&&bearImp))) pst=10;
         if(pst==10 && (oppBOS||physCapacityLow)) pst=11;
         if(pst==11 && ((dir==1&&lo<fbv)||(dir==-1&&hi>ftv))) pst=12;
         if(pst==12 && ((dir==1&&bullCH)||(dir==-1&&bearCH))) pst=13;
      }
      int phase=pst;
      if(phase==5 && dir==-1) phase=6;
      if(phase==13 && dir==-1) phase=14;
      double wp=pst==0?5.0:pst==1?15.0:pst==2?25.0:pst==3?33.0:pst==4?42.0:pst==5?55.0:pst==7?65.0:pst==8?75.0:pst==9?85.0:pst==10?90.0:pst==11?94.0:pst==12?97.0:100.0;
      double cm=fmin2(convScore,100.0);
      double mf=fmin2(fmax2(expScore,fmax2(absScore,convScore))*0.70+(dir!=0?30.0:0.0),100.0);
      double frzS=fmin2((eLong||eShort?50.0:0.0)+expScore*0.30+convScore*0.20,100.0);
      O.dir[j]=wdir; O.ph[j]=phase; O.sh[j]=curSH; O.sl[j]=curSL; O.psh[j]=prSH; O.psl[j]=prSL;
      O.bos[j]=bosOut; O.ch[j]=chOut; O.p4h[j]=p4h; O.p4l[j]=p4l; O.inv[j]=inv; O.tgt[j]=tgt;
      O.ft[j]=ftv; O.fb[j]=fbv; O.fs[j]=frzS; O.wp[j]=wp; O.cm[j]=cm; O.mf[j]=mf;
      O.comp[j]=compIdx; O.rec[j]=recBrk; O.dom[j]=recDom;
   }
}


//==================================================================
// V60 CONTEXT STATE + OUTPUTS
//==================================================================
SEV60     v1,v2,v3,v4,v5,v6;          // ladder rungs 1..6 (rung3 = chart = canonical)
FUPoolOut sfpMN,sfpW,sfpD,sfpH4,sfpH1,sfpM15,sfpM5;

//--- node registry ---
double sn_px[],sn_mid[],sn_sc[]; int sn_dir[],sn_wt[],sn_state[],sn_bar[],sn_rev[];
double sn_pv[7];                       // last pushed tip per TF (MN,W,D,H4,H1,M15,M5)

//--- v60 FEATURE outputs (last closed bar) -- NO decision layer ---
int    ctx_waveDir=0, ctx_stackDir=0, ctx_netBias=0, ctx_pdir=0, ctx_timeDir=0;
double ctx_stackPct=0, ctx_pressure=0, ctx_residual=0, ctx_attractorScore=0, ctx_timeAlign=0, ctx_timeConflict=0;
int    ctx_resCode=0, ctx_eligN=0;
string ctx_phase="Point 4 Origin";
double ctx_entry=NA, ctx_stop=NA, ctx_t1=NA, ctx_t2=NA, ctx_t3=NA, ctx_attractorPx=NA, ctx_netTarget=NA, ctx_fezHi=NA, ctx_fezLo=NA;
//--- freshest FU node (the indicator's "extreme entry") ---
bool   ctx_fuFresh=false; int ctx_fuDir=0; double ctx_fuTip=NA, ctx_fuMid=NA;
//--- curve life (management) ---
double ctx_life=50.0, ctx_cpForce=0; string ctx_cpState="NEUTRAL", ctx_alive="WEAKENING";
//--- narrative lineage / ownership migration (context) ---
double ctx_narrative=50.0; string ctx_narrState="HOLDING"; bool ctx_converging=false;
double ctx_chainVitality=50.0, ctx_mig50=NA, ctx_mig618=NA, ctx_retrX=50.0;
//--- F72 campaign ownership: building (expansion -> flip) vs terminal (at the HTF FU flip zone) ---
bool   ctx_atFlip=false;          // price has reached / is inside the HTF FU flip zone
string ctx_campaign="EXPANSION";  // EXPANSION (building) / TERMINAL (at flip)
double ctx_distFlipAtr=0.0;       // distance to the flip magnet in ATR
bool   ctx_fuMerged=false;        // recursive curve respected the parent FU -> camp merged back (Principle 9)
//--- F72 Wyckoff terminal shift counter (spring/test/LPS1/LPS2 - "always four") ---
int    ctx_termShifts=0;          // recursive change-of-character shifts counted inside the flip zone
int    ctx_termExpected=4;        // expected shifts to complete the terminal sequence (compression-modulated)
bool   ctx_termComplete=false;    // terminal entry cycle has matured (enough shifts done)
int    ctx_termM1Cycles=0;        // finer induction/liquidation sub-cycles on M1 inside the terminal
//--- persistent M1 terminal sub-cycle state ---
int    g_termPrevDirM1=0;
//--- F72 Part 3: 61/70/78 manipulation band vs true induction at the lowest flip ---
bool   ctx_inManipBand=false;     // price is in the 0.618-0.786 fib band (manipulation/displacement, NOT entry)
double ctx_lowestFlip=NA;         // the lowest active on-bias flip = true S/D
bool   ctx_atTrueInduction=false; // price is at the lowest flip (true induction zone = prime entry)
bool   ctx_failureSwing=false;    // sweep beyond the true flip then reclaim in compression = spring (fast entry)
//--- ARC v2 (SYMPHONY port): convex curved target trajectory ---
double ctx_arcApex=NA;            // the projected convex APEX (curve target) for the current wave
double ctx_arcNow=NA;             // time-projected expected price along the arc (wave-progress t)
int    ctx_arcDir=0;              // direction the arc projects (+1 up / -1 down)
double ctx_cExtreme=NA;           // raw current leg extreme (published by ContextRun, consumed by ComputeARC)
//--- persistent terminal-counter state (updated once per bar) ---
bool   g_termActive=false; int g_termShifts=0; int g_termPrevDirM5=0;
//--- TIE detail ---
string ctx_h1Timing="--"; double ctx_wp=0, ctx_atr=0;

double f_authSen(const int i){ return(sn_sc[i]+sn_wt[i]*4.0+sn_rev[i]*3.0); }
void SnPush(const double px,const double mid,const int dir,const double sc,const int wt,const int barI)
{
   int s=ArraySize(sn_px);
   ArrayResize(sn_px,s+1);ArrayResize(sn_mid,s+1);ArrayResize(sn_sc,s+1);ArrayResize(sn_dir,s+1);
   ArrayResize(sn_wt,s+1);ArrayResize(sn_state,s+1);ArrayResize(sn_bar,s+1);ArrayResize(sn_rev,s+1);
   sn_px[s]=px; sn_mid[s]=mid; sn_dir[s]=dir; sn_sc[s]=sc; sn_wt[s]=wt; sn_state[s]=0; sn_bar[s]=barI; sn_rev[s]=0;
   if(ArraySize(sn_px)>sIn_nodeMax){ ArrayRemove(sn_px,0,1);ArrayRemove(sn_mid,0,1);ArrayRemove(sn_sc,0,1);ArrayRemove(sn_dir,0,1);ArrayRemove(sn_wt,0,1);ArrayRemove(sn_state,0,1);ArrayRemove(sn_bar,0,1);ArrayRemove(sn_rev,0,1); }
}

//--- read the current (forming) cycle bar + prior extremes for the TIE ---
void CycleRead(const ENUM_TIMEFRAMES tf,double &o,double &h,double &l,double &ph,double &pl)
{
   o=NA;h=NA;l=NA;ph=NA;pl=NA;
   MqlRates r[]; ArraySetAsSeries(r,false);
   int got=CopyRates(_Symbol,tf,0,4,r); if(got<2) return;
   int cur=got-1, prv=got-2;
   o=r[cur].open; h=r[cur].high; l=r[cur].low; ph=r[prv].high; pl=r[prv].low;
}

//==================================================================
// SENSEEI DRIVER -- full recompute -> sets ctx_* for last closed bar
//==================================================================
void ContextRun(const int bars)
{
   TFData d; if(!LoadTF(_Period,bars,d)) return;
   int N=d.n; int warmup=MathMax(2*structLen,2*pivotLen)+effLen+10;
   if(N<warmup+5) return;
   int last=N-2;

   //--- chart ATR + EMA50 ---
   double atrC[]; ATRarr(d.h,d.l,d.c,atrC,atrLen);
   double emaC[]; EMAarr(d.c,emaC,50);

   //--- ladder structure engines (rung3 = chart = canonical) ---
   ComputeSE_V60(SenLadder(1),bars,pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen,v1);
   ComputeSE_V60(SenLadder(2),bars,pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen,v2);
   ComputeSE_V60(SenLadder(3),bars,pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen,v3);
   ComputeSE_V60(SenLadder(4),bars,pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen,v4);
   ComputeSE_V60(SenLadder(5),bars,pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen,v5);
   ComputeSE_V60(SenLadder(6),bars,pivotLen,structLen,atrLen,effThresh,dispThresh,convMult,impulseAtrMult,chochBufferATR,effLen,v6);

   //--- FU pools for the fixed node ladder ---
   ComputeFUPool(PERIOD_MN1,bars,sIn_wickFrac,sfpMN);
   ComputeFUPool(PERIOD_W1, bars,sIn_wickFrac,sfpW);
   ComputeFUPool(PERIOD_D1, bars,sIn_wickFrac,sfpD);
   ComputeFUPool(PERIOD_H4, bars,sIn_wickFrac,sfpH4);
   ComputeFUPool(PERIOD_H1, bars,sIn_wickFrac,sfpH1);
   ComputeFUPool(PERIOD_M15,bars,sIn_wickFrac,sfpM15);
   ComputeFUPool(PERIOD_M5, bars,sIn_wickFrac,sfpM5);

   //--- rebuild node registry over the window ---
   ArrayResize(sn_px,0);ArrayResize(sn_mid,0);ArrayResize(sn_sc,0);ArrayResize(sn_dir,0);
   ArrayResize(sn_wt,0);ArrayResize(sn_state,0);ArrayResize(sn_bar,0);ArrayResize(sn_rev,0);
   for(int k=0;k<7;k++) sn_pv[k]=NA;
   int wts[7]={9,8,7,6,5,4,3};
   for(int j=warmup;j<=last;j++){
      datetime ct=d.t[j]; double clj=d.c[j];
      for(int k=0;k<7;k++){
         int vld=0; double tip=NA,mid=NA; int dr=0; double sc=0;
         if(k==0){ vld=MapValI(sfpMN.t,sfpMN.valid,sfpMN.n,ct); tip=MapVal(sfpMN.t,sfpMN.tip,sfpMN.n,ct); mid=MapVal(sfpMN.t,sfpMN.mid,sfpMN.n,ct); dr=MapValI(sfpMN.t,sfpMN.dir,sfpMN.n,ct); sc=MapVal(sfpMN.t,sfpMN.score,sfpMN.n,ct); }
         else if(k==1){ vld=MapValI(sfpW.t,sfpW.valid,sfpW.n,ct); tip=MapVal(sfpW.t,sfpW.tip,sfpW.n,ct); mid=MapVal(sfpW.t,sfpW.mid,sfpW.n,ct); dr=MapValI(sfpW.t,sfpW.dir,sfpW.n,ct); sc=MapVal(sfpW.t,sfpW.score,sfpW.n,ct); }
         else if(k==2){ vld=MapValI(sfpD.t,sfpD.valid,sfpD.n,ct); tip=MapVal(sfpD.t,sfpD.tip,sfpD.n,ct); mid=MapVal(sfpD.t,sfpD.mid,sfpD.n,ct); dr=MapValI(sfpD.t,sfpD.dir,sfpD.n,ct); sc=MapVal(sfpD.t,sfpD.score,sfpD.n,ct); }
         else if(k==3){ vld=MapValI(sfpH4.t,sfpH4.valid,sfpH4.n,ct); tip=MapVal(sfpH4.t,sfpH4.tip,sfpH4.n,ct); mid=MapVal(sfpH4.t,sfpH4.mid,sfpH4.n,ct); dr=MapValI(sfpH4.t,sfpH4.dir,sfpH4.n,ct); sc=MapVal(sfpH4.t,sfpH4.score,sfpH4.n,ct); }
         else if(k==4){ vld=MapValI(sfpH1.t,sfpH1.valid,sfpH1.n,ct); tip=MapVal(sfpH1.t,sfpH1.tip,sfpH1.n,ct); mid=MapVal(sfpH1.t,sfpH1.mid,sfpH1.n,ct); dr=MapValI(sfpH1.t,sfpH1.dir,sfpH1.n,ct); sc=MapVal(sfpH1.t,sfpH1.score,sfpH1.n,ct); }
         else if(k==5){ vld=MapValI(sfpM15.t,sfpM15.valid,sfpM15.n,ct); tip=MapVal(sfpM15.t,sfpM15.tip,sfpM15.n,ct); mid=MapVal(sfpM15.t,sfpM15.mid,sfpM15.n,ct); dr=MapValI(sfpM15.t,sfpM15.dir,sfpM15.n,ct); sc=MapVal(sfpM15.t,sfpM15.score,sfpM15.n,ct); }
         else { vld=MapValI(sfpM5.t,sfpM5.valid,sfpM5.n,ct); tip=MapVal(sfpM5.t,sfpM5.tip,sfpM5.n,ct); mid=MapVal(sfpM5.t,sfpM5.mid,sfpM5.n,ct); dr=MapValI(sfpM5.t,sfpM5.dir,sfpM5.n,ct); sc=MapVal(sfpM5.t,sfpM5.score,sfpM5.n,ct); }
         if(vld==1 && !naf(tip) && (naf(sn_pv[k])||tip!=sn_pv[k])){ SnPush(tip,mid,dr,sc,wts[k],j); sn_pv[k]=tip; }
      }
      //--- update node states with this bar ---
      double atrj=atrC[j];
      for(int i=0;i<ArraySize(sn_px);i++){
         if(sn_state[i]==2) continue;
         double np=sn_px[i]; int nd=sn_dir[i]; int age=j-sn_bar[i];
         if(nd==-1?clj>np:clj<np) sn_state[i]=2;
         else {
            if(MathAbs(clj-np)<atrj*0.25) sn_rev[i]++;
            sn_state[i]= age>sIn_historyBars*sn_wt[i]?3: age>sIn_dormantBars*sn_wt[i]?1:0;
         }
      }
   }

   //--- narrative lineage / chain vitality (canonical wave) ---
   double narrDir=0, legX=NA, legPB=0, narrative=50.0; int supV=0, degV=0, seqCnt=0;
   double seqLast=NA, seqPrev=NA; double compHist[]; ArrayResize(compHist,0);
   for(int j=warmup;j<=last;j++){
      datetime ct=d.t[j]; double clj=d.c[j], hj=d.h[j], lj=d.l[j];
      double inv=MapVal(v3.t,v3.inv,v3.n,ct);
      int cdir=f_waveDirByOrigin(inv,clj,(int)nz(MapVal(v3.t,v3.dir,v3.n,ct)));
      double comp=nz(MapVal(v3.t,v3.comp,v3.n,ct));
      int hs=ArraySize(compHist); ArrayResize(compHist,hs+1); compHist[hs]=comp;
      double tighten=(hs>=6)?comp-compHist[hs-6]:0.0;
      if(cdir!=(int)narrDir){ narrDir=cdir; legX=cdir==1?hj:(cdir==-1?lj:NA); legPB=0; narrative=50.0; supV=0; degV=0; seqLast=NA; seqPrev=NA; seqCnt=0; }
      if(cdir!=0 && !naf(inv)){
         bool newX=cdir==1?hj>nz(legX,hj):lj<nz(legX,lj);
         if(newX){
            if(legPB>6.0){
               bool sup=legPB<=50.0 && tighten>=-1.0;
               bool deg=legPB>=62.0 || tighten<-3.0;
               int vote=sup?1:deg?-1:0;
               supV+=vote==1?1:0; degV+=vote==-1?1:0;
               narrative=clamp(narrative+vote*12.0+(tighten>0?3.0:-3.0),0.0,100.0);
               seqPrev=seqLast; seqLast=legPB; seqCnt++;
            }
            legX=cdir==1?hj:lj; legPB=0;
         } else {
            double pbd=MathAbs(nz(legX,clj)-inv)>1e-9?MathAbs(nz(legX,clj)-clj)/MathAbs(nz(legX,clj)-inv)*100.0:0.0;
            legPB=fmax2(legPB,pbd);
         }
      }
   }
   string narrState=narrative>=65.0?"STRENGTHENING":narrative<=35.0?"WEAKENING":"HOLDING";
   bool converging=seqCnt>=2 && !naf(seqLast) && !naf(seqPrev) && seqLast<seqPrev;
   double chainVitality=converging?fmin2(100.0,narrative+10.0):fmax2(0.0,narrative-10.0);

   //--- network aggregates at last bar ---
   double clL=d.c[last], atrL=atrC[last];
   int eligN=0; double bullAuth=0,bearAuth=0; int domIdx=-1; double domAuth=0;
   //--- netBias: highest-weight valid TF dir, else EMA50 ---
   datetime ctL=d.t[last];
   int netBias=0;
   for(int k=0;k<7;k++){
      int vld=0,dr=0;
      if(k==0){ vld=MapValI(sfpMN.t,sfpMN.valid,sfpMN.n,ctL); dr=MapValI(sfpMN.t,sfpMN.dir,sfpMN.n,ctL); }
      else if(k==1){ vld=MapValI(sfpW.t,sfpW.valid,sfpW.n,ctL); dr=MapValI(sfpW.t,sfpW.dir,sfpW.n,ctL); }
      else if(k==2){ vld=MapValI(sfpD.t,sfpD.valid,sfpD.n,ctL); dr=MapValI(sfpD.t,sfpD.dir,sfpD.n,ctL); }
      else if(k==3){ vld=MapValI(sfpH4.t,sfpH4.valid,sfpH4.n,ctL); dr=MapValI(sfpH4.t,sfpH4.dir,sfpH4.n,ctL); }
      else if(k==4){ vld=MapValI(sfpH1.t,sfpH1.valid,sfpH1.n,ctL); dr=MapValI(sfpH1.t,sfpH1.dir,sfpH1.n,ctL); }
      else if(k==5){ vld=MapValI(sfpM15.t,sfpM15.valid,sfpM15.n,ctL); dr=MapValI(sfpM15.t,sfpM15.dir,sfpM15.n,ctL); }
      else { vld=MapValI(sfpM5.t,sfpM5.valid,sfpM5.n,ctL); dr=MapValI(sfpM5.t,sfpM5.dir,sfpM5.n,ctL); }
      if(vld==1 && dr!=0){ netBias=dr; break; }
   }
   if(netBias==0) netBias=clL>emaC[last]?1:clL<emaC[last]?-1:0;

   int attrIdx=-1; double attrRank=-1; double fezHi=NA,fezLo=NA,fezHiA=0,fezLoA=0;
   double lowFlipPx=NA;   // the LOWEST active on-bias flip (deepest support / highest resistance) = true S/D
   for(int i=0;i<ArraySize(sn_px);i++){
      int st=sn_state[i]; double a=f_authSen(i);
      if(st!=2 && a>=sIn_authMin){
         double np=sn_px[i]; int nd=sn_dir[i]; int wt=sn_wt[i];
         eligN++;
         if(nd==1) bullAuth+=a; else if(nd==-1) bearAuth+=a;
         if(a>domAuth){ domAuth=a; domIdx=i; }
         bool onBias=netBias==-1?np<clL:np>clL;
         if(onBias){ double rk=wt*1000.0+a; if(rk>attrRank){ attrRank=rk; attrIdx=i; } }
         if(np>clL && a>fezHiA){ fezHi=np; fezHiA=a; }
         if(np<clL && a>fezLoA){ fezLo=np; fezLoA=a; }
         //--- lowest flip = the deepest demand below (bull) / highest supply above (bear) ---
         if(netBias>=0 && nd==1 && np<clL && (naf(lowFlipPx)||np<lowFlipPx)) lowFlipPx=np;
         if(netBias<=0 && nd==-1&& np>clL && (naf(lowFlipPx)||np>lowFlipPx)) lowFlipPx=np;
      }
   }
   double pressure=(bullAuth+bearAuth)>0?(bullAuth-bearAuth)/(bullAuth+bearAuth)*100.0:0.0;
   int pdir=pressure>12?1:pressure<-12?-1:0;
   double netTarget=attrIdx>=0?sn_px[attrIdx]:NA;

   //--- map canonical (rung3) + ladder rung dirs at last bar ---
   int  c_ph=(int)nz(MapVal(v3.t,v3.ph,v3.n,ctL));
   double c_inv=MapVal(v3.t,v3.inv,v3.n,ctL), c_tgt=MapVal(v3.t,v3.tgt,v3.n,ctL);
   double c_ft=MapVal(v3.t,v3.ft,v3.n,ctL), c_fb=MapVal(v3.t,v3.fb,v3.n,ctL);
   double c_p4h=MapVal(v3.t,v3.p4h,v3.n,ctL), c_p4l=MapVal(v3.t,v3.p4l,v3.n,ctL);
   double c_wp=nz(MapVal(v3.t,v3.wp,v3.n,ctL)), c_comp=nz(MapVal(v3.t,v3.comp,v3.n,ctL)), c_rec=nz(MapVal(v3.t,v3.rec,v3.n,ctL));
   double c_mf=nz(MapVal(v3.t,v3.mf,v3.n,ctL));
   int waveDir=f_waveDirByOrigin(c_inv,clL,(int)nz(MapVal(v3.t,v3.dir,v3.n,ctL)));
   string phaseStr=f_phaseStrV60(c_ph);

   int d1=f_waveDirByOrigin(MapVal(v1.t,v1.inv,v1.n,ctL),clL,(int)nz(MapVal(v1.t,v1.dir,v1.n,ctL)));
   int d2=f_waveDirByOrigin(MapVal(v2.t,v2.inv,v2.n,ctL),clL,(int)nz(MapVal(v2.t,v2.dir,v2.n,ctL)));
   int d4=f_waveDirByOrigin(MapVal(v4.t,v4.inv,v4.n,ctL),clL,(int)nz(MapVal(v4.t,v4.dir,v4.n,ctL)));
   int d5=f_waveDirByOrigin(MapVal(v5.t,v5.inv,v5.n,ctL),clL,(int)nz(MapVal(v5.t,v5.dir,v5.n,ctL)));
   int d6=f_waveDirByOrigin(MapVal(v6.t,v6.inv,v6.n,ctL),clL,(int)nz(MapVal(v6.t,v6.dir,v6.n,ctL)));
   int sb=(d1==1?1:0)+(d2==1?1:0)+(waveDir==1?1:0)+(d4==1?1:0)+(d5==1?1:0)+(d6==1?1:0);
   int sbe=(d1==-1?1:0)+(d2==-1?1:0)+(waveDir==-1?1:0)+(d4==-1?1:0)+(d5==-1?1:0)+(d6==-1?1:0);
   int stackDir=sb>sbe?1:sbe>sb?-1:0;
   double stackPct=(double)MathMax(sb,sbe)/6.0*100.0;
   double t2=MapVal(v4.t,v4.tgt,v4.n,ctL), t3=MapVal(v5.t,v5.tgt,v5.n,ctL);

   //--- TIE (cycle stack MN/W/D/H4/H1) ---
   double mo,mh,ml,mph,mpl; CycleRead(PERIOD_MN1,mo,mh,ml,mph,mpl);
   double wo,wh,wl,wph,wpl; CycleRead(PERIOD_W1, wo,wh,wl,wph,wpl);
   double do_,dh,dl,dph,dpl; CycleRead(PERIOD_D1, do_,dh,dl,dph,dpl);
   double ho,hh,hl,hph,hpl; CycleRead(PERIOD_H4, ho,hh,hl,hph,hpl);
   double o1,h1,l1,ph1,pl1; CycleRead(PERIOD_H1, o1,h1,l1,ph1,pl1);
   int tBull=(!naf(mo)&&clL>mo?1:0)+(!naf(wo)&&clL>wo?1:0)+(!naf(do_)&&clL>do_?1:0)+(!naf(ho)&&clL>ho?1:0)+(!naf(o1)&&clL>o1?1:0);
   int tBear=(!naf(mo)&&clL<mo?1:0)+(!naf(wo)&&clL<wo?1:0)+(!naf(do_)&&clL<do_?1:0)+(!naf(ho)&&clL<ho?1:0)+(!naf(o1)&&clL<o1?1:0);
   int timeDir=tBull>tBear?1:tBear>tBull?-1:0;
   double timeAlign=(tBull+tBear)>0?(double)MathMax(tBull,tBear)/(tBull+tBear)*100.0:50.0;
   double timeConflict=100.0-timeAlign;
   bool h1Ht=!naf(h1)&&!naf(ph1)&&h1>ph1, h1Lt=!naf(l1)&&!naf(pl1)&&l1<pl1;
   double h1pos=(!naf(h1)&&!naf(l1)&&h1>l1)?(clL-l1)/fmax2(h1-l1,_Point):0.5;
   double h1LowProb=(h1Lt&&!h1Ht)?30.0:(h1Ht&&!h1Lt)?70.0:MathRound(h1pos*100.0);
   string h1Timing=(h1Ht&&h1Lt)?"COMPLETION":h1LowProb>=55?"LOW FIRST":h1LowProb<=45?"HIGH FIRST":"BALANCED";

   //--- EDE / RE / EAE (compact, from canonical phase) ---
   int ede_state=(phaseStr=="Point 4 Origin"||phaseStr=="Expansion")?1:phaseStr=="Expansion Pre-Convexity"?2:phaseStr=="Expansion Induction"?3:phaseStr=="Expansion Liquidity"?4:(phaseStr=="New High"||phaseStr=="New Low")?5:6;
   double dissProg=fmin2((ede_state>=2?25.0:0.0)+(ede_state>=3?25.0:0.0)+(ede_state>=4?25.0:0.0)+(ede_state>=5?25.0:0.0),100.0);
   double residual=clamp(100.0-c_wp,0.0,100.0);
   int resCode=(phaseStr=="Demand Return"||phaseStr=="Supply Return")?2:(phaseStr=="New High"||phaseStr=="New Low"||phaseStr=="Terminal Curve"||phaseStr=="Liquidation")?1:0;
   double attractorPx=resCode==0?(waveDir==1?nz(c_fb,clL-atrL*2.0):nz(c_ft,clL+atrL*2.0)):(waveDir==1?nz(c_p4l,clL-atrL):nz(c_p4h,clL+atrL));
   if(naf(attractorPx)) attractorPx=netTarget;
   double attractorScore=fmin2(residual*0.40+(resCode==0?30.0:resCode==1?20.0:5.0)+(!naf(attractorPx)?fmax2(0.0,30.0-MathAbs(clL-attractorPx)/fmax2(atrL,1e-10)*5.0):0.0),100.0);

   //--- attack / level context (entry zone mid) ---
   double entry=(!naf(c_ft)&&!naf(c_fb))?(c_ft+c_fb)/2.0:NA;

   //--- F72 curve life ("is the trade alive?") ---
   double cExtreme=waveDir==1?MapVal(v3.t,v3.sh,v3.n,ctL):waveDir==-1?MapVal(v3.t,v3.sl,v3.n,ctL):NA;
   double retrX=(naf(cExtreme)||naf(c_inv)||cExtreme==c_inv)?50.0:fmin2(100.0,MathAbs(cExtreme-clL)/MathAbs(cExtreme-c_inv)*100.0);
   bool attacking=waveDir==1?(!naf(cExtreme)&&d.h[last]>=cExtreme):waveDir==-1?(!naf(cExtreme)&&d.l[last]<=cExtreme):false;
   bool progressing=attacking;
   int budgetDepth=MathMax(1,MathMin(4,1+(int)MathRound(c_comp/33.0)));
   bool recursionComplete=budgetDepth>0 && (int)c_rec>=budgetDepth;
   double cpForce=clamp(c_comp*0.50+residual*0.20-(int)c_rec*12.0+8.0,0.0,100.0);
   string cpState=cpForce>=60.0?"PERSISTING":cpForce<=35.0?"LEAKING":"NEUTRAL";
   double life=clamp(cpForce*0.45+residual*0.30-(recursionComplete&&!progressing?25.0:0.0)-(cpState=="LEAKING"&&!progressing?20.0:0.0)+(progressing?28.0:0.0)+(retrX<25.0?16.0:retrX<45.0?6.0:retrX>75.0?-12.0:0.0)+10.0,0.0,100.0);
   string aliveTx=(progressing&&life>=45.0)?"ALIVE - ATTACKING":life>=60.0?"ALIVE - HOLD":life<=32.0?"DEAD - FLIP":"WEAKENING - MANAGE";
   //--- ownership migration band (0.5 / 0.618 of the owner leg) ---
   double mig50=(naf(c_inv)||naf(cExtreme)||cExtreme==c_inv)?NA:cExtreme+0.5*(c_inv-cExtreme);
   double mig618=(naf(c_inv)||naf(cExtreme)||cExtreme==c_inv)?NA:cExtreme+0.618*(c_inv-cExtreme);

   //--- FU extreme entry node:  (a) a node that just VALIDATED on the last closed bar
   //--- (the indicator printing a fresh circle at the extreme), OR
   //--- (b) price RETURNING to / TAPPING a recent, valid, high-authority node
   //--- (the indicator's circle being revisited -- enter AT that extreme). ---
   bool fuFresh=false; int fuDir=0; double fuTip=NA, fuMid=NA; double fuAuth=-1.0;
   double fuHi=d.h[last], fuLo=d.l[last]; double fuTap=atrL*sIn_tapAtr;
   for(int fi=0;fi<ArraySize(sn_px);fi++){
      if(sn_state[fi]==2) continue;                         // skip invalidated nodes
      double a=f_authSen(fi);
      if(a<sIn_authMin) continue;
      double np=sn_px[fi]; int nd=sn_dir[fi];
      bool justFormed=(sn_bar[fi]==last);
      // demand node (dir +1, sits below price): tapped when the bar low reaches it but close holds above
      // supply node (dir -1, sits above price): tapped when the bar high reaches it but close holds below
      bool tapped=(nd==1 ? (fuLo<=np+fuTap && clL>=np)
                 : nd==-1? (fuHi>=np-fuTap && clL<=np) : false);
      bool recent=((last-sn_bar[fi])<=sIn_tapMaxAge);
      if((justFormed || (tapped && recent)) && nd!=0 && a>fuAuth){
         fuAuth=a; fuFresh=true; fuDir=nd; fuTip=np; fuMid=sn_mid[fi];
      }
   }

   //--- F72 CAMPAIGN OWNERSHIP -------------------------------------------------
   //  Building (EXPANSION) = trending toward the HTF flip; TERMINAL = price has
   //  reached the FU flip zone, where induction/liquidation/entry-cycle happens.
   //  The FU flip zone is already mapped (network attractor / FEZ corridor).
   double _flipMag = !naf(attractorPx)?attractorPx : nz(netTarget,c_tgt);
   bool   _inFez   = (!naf(fezHi)&&!naf(fezLo)&&clL<=fezHi&&clL>=fezLo);
   double _distMag = (!naf(_flipMag))?MathAbs(clL-_flipMag):NA;
   ctx_distFlipAtr = (!naf(_distMag)&&atrL>0)?_distMag/atrL : 5.0;
   ctx_atFlip   = _inFez || (!naf(_distMag) && _distMag<=atrL*1.0);
   ctx_campaign = ctx_atFlip ? "TERMINAL (at flip)" : "EXPANSION (building)";
   //  Principle 9 -- FU camp merge: a fresh FU node that sits at the SAME flip zone as
   //  the network attractor means the recursive curve respected the parent FU, so the
   //  campaign merged back into the parent (not a genuinely new camp).
   ctx_fuMerged = (ctx_fuFresh && !naf(ctx_fuTip) && !naf(_flipMag) && atrL>0 && MathAbs(ctx_fuTip-_flipMag)<=atrL*0.75);

   //  Wyckoff terminal sequence: count recursive change-of-character shifts WHILE inside the
   //  flip zone (the spring/test/LPS1/LPS2 - "always four"). Entry matures on the completing
   //  shift, not the first strike. Compression sets how many shifts to expect (tight -> fewer/faster).
   //  RESET: when price expands away OR when an expansion phase begins (not just !ctx_atFlip).
   //  ACTIVATE: only during transition/terminal phases at the flip zone.
   int _expShifts=(int)clamp(nz((double)cur_expRecDepth,3.0),3.0,5.0);   // F72: Wyckoff terminal is ~4 shifts, min 3
   if(ctx_fuMerged) _expShifts=(int)MathMin(_expShifts+3,7);   // Principle 9: camp merged back -> cycle still owes ~3 more recursions
   // RESET on: leaving flip zone OR expansion phase begins (wave is running, not transitioning)
   bool _inExpansionPhase = (cur_ie1aPhase=="Expansion"||cur_ie1aPhase=="New High"||cur_ie1aPhase=="New Low"||
        cur_ie1aPhase=="Expansion Pre-Convexity"||cur_ie1aPhase=="Expansion Induction"||cur_ie1aPhase=="Expansion Liquidity");
   if(!ctx_atFlip || _inExpansionPhase){ g_termActive=false; g_termShifts=0; ctx_termM1Cycles=0; g_termPrevDirM1=cur_dirM1; }
   else {
      if(!g_termActive){ g_termActive=true; g_termShifts=0; g_termPrevDirM5=cur_dirM5; ctx_termM1Cycles=0; g_termPrevDirM1=cur_dirM1; }
      if(cur_dirM5!=0 && cur_dirM5!=g_termPrevDirM5){ g_termShifts++; g_termPrevDirM5=cur_dirM5; }   // M5 CHoCH inside the zone = one shift
      if(cur_dirM1!=0 && cur_dirM1!=g_termPrevDirM1){ ctx_termM1Cycles++; g_termPrevDirM1=cur_dirM1; } // finer M1 induction/liquidation sub-cycle
   }
   ctx_termShifts=g_termShifts; ctx_termExpected=_expShifts;
   //  terminal completes when M5 shifts reach the expected count, OR (on a larger-TF owner where
   //  the terminal only nests on M1) when the M1 sub-cycles reach ~2x the expected.
   bool _htfOwner=(cur_curveOwner=="H1"||cur_curveOwner=="H4"||cur_curveOwner=="M15");
   ctx_termComplete=(ctx_atFlip && (g_termShifts>=_expShifts || (_htfOwner && ctx_termM1Cycles>=2*_expShifts)));

   //  Part 3 -- manipulation band vs true induction. The 0.618/0.70/0.786 fib band of the
   //  owner leg is where participants manipulate (displacement, NOT the entry). True induction
   //  happens at the LOWEST flip (deepest demand / highest supply = true S/D). Entries align
   //  to the true flip, not the manipulation wicks.
   ctx_lowestFlip = lowFlipPx;
   ctx_atTrueInduction = (!naf(lowFlipPx) && atrL>0 && MathAbs(clL-lowFlipPx)<=atrL*0.75);
   //  failure swing (spring): in High/Extreme compression price sweeps BEYOND the true flip
   //  then reclaims it on the close - that IS the terminal spring, entry comes fast.
   bool _comp=(cur_compRegime=="High"||cur_compRegime=="Extreme");
   bool _fsL=(!naf(lowFlipPx)&&netBias>=0&&d.l[last]<lowFlipPx&&clL>lowFlipPx);
   bool _fsS=(!naf(lowFlipPx)&&netBias<=0&&d.h[last]>lowFlipPx&&clL<lowFlipPx);
   ctx_failureSwing=(ctx_atFlip && _comp && (_fsL||_fsS));
   ctx_inManipBand = false;
   if(!naf(cExtreme) && !naf(c_inv) && cExtreme!=c_inv){
      double _f618=cExtreme+0.618*(c_inv-cExtreme);
      double _f786=cExtreme+0.786*(c_inv-cExtreme);
      double _bLo=fmin2(_f618,_f786), _bHi=fmax2(_f618,_f786);
      ctx_inManipBand = (clL>=_bLo && clL<=_bHi) && !ctx_atTrueInduction;   // in fib band but NOT at the true flip = manipulation
   }

   //--- publish FEATURE outputs only (NO Senseei decision layer) ---
   ctx_fuFresh=fuFresh; ctx_fuDir=fuDir; ctx_fuTip=fuTip; ctx_fuMid=fuMid;
   ctx_waveDir=waveDir; ctx_stackDir=stackDir; ctx_netBias=netBias; ctx_pdir=pdir; ctx_timeDir=timeDir;
   ctx_stackPct=stackPct; ctx_pressure=pressure; ctx_residual=residual; ctx_attractorScore=attractorScore;
   ctx_timeAlign=timeAlign; ctx_timeConflict=timeConflict; ctx_resCode=resCode; ctx_eligN=eligN; ctx_phase=phaseStr;
   ctx_entry=entry; ctx_stop=c_inv; ctx_t1=nz(c_tgt,attractorPx); ctx_t2=t2; ctx_t3=t3; ctx_attractorPx=attractorPx; ctx_netTarget=netTarget; ctx_fezHi=fezHi; ctx_fezLo=fezLo;
   ctx_life=life; ctx_cpForce=cpForce; ctx_cpState=cpState; ctx_alive=aliveTx; ctx_h1Timing=h1Timing; ctx_wp=c_wp; ctx_atr=atrL;
   ctx_narrative=narrative; ctx_narrState=narrState; ctx_converging=converging; ctx_chainVitality=chainVitality;
   ctx_mig50=mig50; ctx_mig618=mig618; ctx_retrX=retrX;
   //--- ARC v2 (SYMPHONY port): publish the raw leg extreme only; the convex apex is built in
   //  ComputeARC() (EA section) so it can use the ARC inputs declared there (declare-before-use). ---
   ctx_cExtreme=cExtreme;
}


//===================================================================
//  EXPERT ADVISOR (from Letra37_EA.mq5)
//===================================================================

//==================================================================
// EA INPUT ENUMS
//==================================================================
enum ENUM_SIG_SOURCE { SIG_ENGINE, SIG_V72, SIG_EITHER, SIG_BOTH };   // arrows / DOE / either(OR) / both(AND)
enum ENUM_LOT_MODE   { LOT_FIXED, LOT_RISK_PCT };
enum ENUM_SL_MODE    { SL_ENGINE, SL_ATR, SL_FIXED };
//  SPEC AUDIT: ENUM_TP_MODE and ENUM_TRAIL_MODE removed (no TP targets, no trailing).
enum ENUM_MIN_GRADE  { G_APLUS, G_A, G_B, G_C, G_D };

//==================================================================
// EA INPUTS
//==================================================================
input group "Letra37 EA - Execution"
input ENUM_SIG_SOURCE InpSignalSource   = SIG_EITHER;   // Entry source: EITHER=arrow OR DOE (both types), V72=DOE only, ENGINE=arrows only, BOTH=require both
input bool   InpTradeLongs              = true;         // Allow long trades
input bool   InpTradeShorts             = true;         // Allow short trades
input bool   InpReverseOnOpposite       = false;        // Reverse position on opposite signal
input int    InpMaxPositions            = 1;            // Max simultaneous positions (this EA)
input int    InpEngineBars              = 3000;         // Bars recomputed per new bar
input bool   InpUseLimitEntry           = false;        // Use limit at engine entry-mid (else market)
input int    InpPendingExpiryBars       = 6;            // Pending order expiry (bars; 0=GTC)

input group "Letra37 EA - Entry Filters"
input bool          InpRequireErfGate   = true;         // Require ERF entry gate open
input bool          InpRequireHtfAlign  = false;        // Require HTF alignment with trade dir
input double        InpMinConfidence    = 0.0;          // Min DOE confidence % (0=off)

input group "Letra37 EA - Risk / Sizing"
input ENUM_LOT_MODE InpLotMode          = LOT_RISK_PCT; // Position sizing mode
input double        InpFixedLot         = 0.10;         // Fixed lot (LOT_FIXED)
input double        InpRiskPercent      = 1.0;          // Risk % of equity (LOT_RISK_PCT)
input double        InpMaxLot           = 2.0;          // Hard lot cap (reduced from 5: 5 lots/100k was ~3-5% risk/trade -> 96% DD)
input int           InpMaxSpreadPoints  = 0;            // Max spread (points); 0=off (gold spreads are large!)

input group "Letra37 EA - Small Account Mode (toggle)"
input bool          InpSmallAccount       = false;      // TOGGLE: apply small-account sizing/limits below (overrides risk% + lot cap)
input double        InpSmallAcctRiskPct   = 0.5;        // Small-acct: risk % per trade (lower than the standard InpRiskPercent)
input double        InpSmallAcctMaxLot    = 0.10;       // Small-acct: hard lot cap (micro sizing)
input double        InpSmallAcctMaxRiskPct= 2.0;        // Small-acct: SKIP a trade if even the broker-minimum lot would risk more than this % (can't size smaller)
input int           InpSmallAcctMaxTrades = 5;          // Small-acct: max new trades/day (0=use the standard limit)

input group "Letra37 EA - Stop Loss"
input ENUM_SL_MODE  InpSLMode           = SL_ENGINE;    // Stop-loss source
input double        InpSLAtrMult        = 1.5;          // SL = ATR * mult (SL_ATR)
input int           InpSLFixedPoints    = 300;          // SL fixed points (SL_FIXED)
input double        InpSLEngineBufATR   = 0.10;         // Extra ATR buffer beyond engine stop
input double        InpMinSLAtr         = 1.5;          // Minimum SL distance in ATR (stops getting stopped out instantly)
input bool          InpUseKeyLevelStop  = true;         // Anchor SL beyond the recent KEY swing high/low (structure)
input int           InpSwingLookback    = 20;           // Bars scanned for the protective key swing high/low
input double        InpKeyLevelBufATR   = 0.80;         // Buffer beyond the key high/low (xATR) - gold wicks are large
input double        InpMaxSLAtr         = 10.0;         // Safety cap on total SL distance (xATR)
input bool          InpCompSizing       = true;         // Recursion-size-aware sizing: compression sets stop distance + partial timing (wide loop=wider stop, failure-swing=tighter)

input group "Letra37 EA - Take Profit"
//  SPEC AUDIT: ALL take-profit logic REMOVED. Campaigns are NOT closed because a reward ratio
//  was reached. The position lives until ownership transfers or the campaign's terminal sequence
//  completes. The broker order has TP=0 (no server TP). Structure SL remains the only hard stop.
//  (Retained as empty group for input-ordering backward compat; inputs deleted.)

input group "Letra37 EA - Trade Management (F72 OWNERSHIP EXITS ONLY)"
//  SPEC AUDIT: break-even, trailing, partial, session-end, thesis-flip, phase-flip, opposite-
//  signal, life-score, narrative -- ALL removed. Recursive waves naturally contain pullbacks,
//  internal liquidation, and ownership oscillation that are NORMAL, not exit signals.
//  EXIT ONLY on (1) ownership transfer, (2) terminal sequence completion, (3) Phase-2 CHOCH
//  against position. These are computed from live engine state each bar.
input int           InpMinHoldBars      = 3;            // Min bars to hold before ANY campaign exit fires (protects against entry-bar reversal noise)
input bool          InpExitOnOwnerTransfer = true;      // EXIT: close when curve OWNERSHIP has fully transferred away from the trade's campaign direction
input double        InpOwnerTransferThresh = 65.0;      // Ownership transfer %: the opposing curve must dominate by at least this % to confirm transfer
input bool          InpExitOnTermComplete  = true;      // EXIT: close when the terminal sequence of the campaign's S/D transition has completed (campaign naturally finished)
input bool          InpExitOnP2CHOCH       = true;      // EXIT: close when a Phase-2 CHOCH prints against the position (internal structure proves campaign failure)
input int           InpP2CHOCHConfirmBars  = 2;         // Bars of continued adverse structure to confirm a genuine P2 CHOCH (vs. wick noise)

input group "Letra37 EA - Session / Guards"
input bool          InpUseSession       = false;        // Restrict NEW ENTRY hours (server time) -- does NOT close existing campaigns
input int           InpSessStartHour    = 7;            // Session start hour
input int           InpSessEndHour      = 20;           // Session end hour
input bool          InpSkipFriday       = false;        // No new trades on Friday
//  SPEC AUDIT: InpCloseAtSessEnd REMOVED (session exit artificially terminates campaigns).
//  SPEC AUDIT: InpMaxDailyLossPct REMOVED (daily risk closure is an external constraint, not curve logic).
input int           InpMaxTradesPerDay  = 20;           // Max new trades per day (0=off) -- limits ENTRIES, not exits

input group "Letra37 EA - Misc"
input ulong         InpMagic            = 370037;       // Magic number
input ulong         InpDeviation        = 20;           // Max slippage (points)
input string        InpComment          = "Letra37";    // Order comment
input bool          InpShowStatus       = true;         // Show status panel (Comment)
input bool          InpDebugEntries     = true;         // Print full entry reasoning to the Experts log (why each trade was taken)
input bool          InpDebugBlocks      = false;        // Also log why entries are BLOCKED (verbose - maps near-misses)
input bool          InpDebugExits       = true;         // Print why each trade was CLOSED / its stop moved (maps early-exit & stop problems)

input group "Letra37 EA - Live Safety"
input bool   InpVerifyTradeAllowed = true;  // LIVE: only place NEW orders when the terminal is connected and algo-trading is permitted (terminal + account + EA)
input int    InpOrderRetries       = 3;     // LIVE: retry a market order this many times on a TRANSIENT broker error (requote / price changed / off-quotes / timeout)
input int    InpRetryWaitMs        = 200;   // LIVE: wait between order retries (ms)
input double InpMarginBufferPct    = 5.0;   // LIVE: keep this % of free margin unused - block a new entry that would consume more
input bool   InpHaltOnLowMargin    = true;  // LIVE: block new entries when the margin level is unsafe

input group "Letra37 EA - v60 Context Filters"
input bool   InpUseV60Context   = true;    // Compute v60 context (network / curve-life / TIE / narrative)
input bool   InpReqNetAgree     = true;    // Require Invisible-Network bias to agree (or neutral)
input bool   InpReqStackAgree   = false;   // Require v60 fractal stack to agree
input bool   InpReqCurveAlive   = false;   // Require curve-life not DEAD at entry (OFF - a high/"alive" life = a MATURE curve near its top; requiring it biased entries to the END of the move. Life is a WINNER-management tool, not an entry filter)
input double InpCurveAliveMin   = 33.0;    // Min curve-life to allow entry
input bool   InpReqNarrative    = false;   // Require narrative not WEAKENING
input bool   InpReqTimeAlign    = false;   // Require time-cycle alignment
input double InpMinTimeAlign    = 55.0;    // Min TIE alignment %
input bool   InpBlockV60Terminal= true;    // Block entry when v60 phase is Liquidation/Terminal against dir
input bool   InpTIEBlockOpposed = true;    // TIE: block entry when a strongly-aligned cycle stack opposes
input double InpTIEStrongAlign  = 60.0;    // TIE: "strong" cycle alignment threshold %
input bool   InpAggressiveEntry = false;   // AGGRESSIVE: also enter on v60 confluence (mid-curve) - off so FU extremes lead
input bool   InpAggReqNet       = true;    // Aggressive: require network bias to agree
input bool   InpAggReqTime      = false;   // Aggressive: respect TIE-opposed block
input bool   InpFUExtremeEntry  = true;    // Enter AT the fresh FU node (the indicator's extreme) - stop beyond the wick tip
input bool   InpFURequireBias   = true;    // FU: only take a node that AGREES with the dominant bias (DOE+network+wave) - stops fading reversals
input bool   InpMultiTFEntry    = true;    // MULTI-TF: enter on a fresh Demand/Supply Return on ANY rung (M1/M3/M5/M15/H1/H4)
input int    InpMinEntryRung     = 1;      // Lowest rung allowed for a multi-TF entry (1=M1 ... 6=H4)
input double InpMinDomTransfer   = 45.0;   // Min dominance-transfer % to treat a Return as an ENTRY CYCLE (below = first strike, wait)
input double InpMinEntryProb     = 0.0;    // Optional: min entry-cycle probability % to allow a multi-TF entry (0 = off)
input bool   InpRequireAtFlip    = false;  // Optional: only take multi-TF entries when price is AT the HTF FU flip zone (terminal side)
input int    InpMinTermShifts    = 3;      // F72: require N terminal shifts (Wyckoff ~4, min 3) before entry; failure-swing / Extreme compression bypasses (fire fast)
input bool   InpAvoidManipBand   = true;   // Skip entries in the 0.618-0.786 manipulation band (displacement trap) unless at true induction
input bool   InpRequireTrueInduction = false; // Optional: only enter at the LOWEST flip (true S/D induction zone)
input bool   InpBlockCounterBias = true;   // VETO any entry (incl. arrows/DOE) opposing the dominant thesis (narrative+DOE+network+wave+stack)
input bool   InpOwnerMustAgree   = true;   // OWNERSHIP-FIRST: a multi-TF entry must agree with the curve OWNER's direction (or owner neutral)

input group "Letra37 EA - v60 Curve-Life Management"
input bool   InpUseCurveLifeExit= false;   // Exit when v60 curve-life goes DEAD (OFF - life score dips mid-run and cut winners)
input double InpCurveDeadBelow  = 32.0;    // life <= this => DEAD (close)
input bool   InpUseMigrationTrail= false;  // Keep stop at ownership-migration 0.618 band while force persists
input bool   InpUseNarrativeMgmt= false;   // Manage with narrative lineage / chain vitality (OFF - same decay-close problem)
input double InpChainExitBelow  = 25.0;    // Exit when chain vitality <= this (story decayed across curves)

input group "Letra37 EA - F72 Entry Cycle (curve ownership)"
input bool   InpRequireEntryCycle = true;  // F72: only enter once the ENTRY CYCLE has begun (build-vs-execute) - applies to ALL sources (arrows/DOE/FU/MTF)
input bool   InpFastEntryOnComp   = true;  // Allow IMMEDIATE entry in Extreme compression or on a failure-swing (compressed/volatile curves fire fast - never miss them)
//  SPEC AUDIT: InpMinEntryRR REMOVED (was testing against a TP target that no longer exists; campaigns have no RR ceiling)
input bool   InpStructureStop     = true;  // Place SL just BEYOND the actual structure price is reacting off (lowest flip / rung invalidation / FU tip) - not generic ATR

input group "Letra37 EA - SYMPHONY Ports (ARC / Exhaustion)"
input double InpAnchorBufATR      = 0.50;  // STOP buffer beyond the curve-origin / invalidation level (xATR). Was 0.25 - gold wicks were spiking just past structure and stopping trades out before the move ran
input bool   InpUseARCTarget      = true;  // TP = the convex ARC apex (curved curve target) when it projects further than the flat attractor
input double InpArcExtMult        = 1.5;   // ARC extension: apex = leg origin + leg*this (the projected curve apex)
input double InpArcConvPower      = 1.5;   // ARC convexity power (time-curvature of the projected path)
input bool   InpUseExhaustionExit = true;  // Composite EXIT: close on ARC-apex + wave/phase collapse + sweep-reclaim (terminal exhaustion)
input double InpArcTolATR         = 0.20;  // How close to the ARC apex counts as "reached" (xATR)

input group "Letra37 EA - SYMPHONY Entry Trigger (precise 'when')"
input bool   InpUseSymphonyTrigger = true; // Require the SYMPHONY EVENT trigger: enter on the closed-bar momentum inflection (the turn), not just on a true state
input bool   InpRequireMomFlip     = true; // Require the bar-to-bar momentum DELTA to flip INTO the trade direction (the inflection bar)
input double InpEntryRetrMin       = 0.30; // Continuation entries: min retracement fraction of the leg (SYMPHONY 0.30)
input double InpEntryRetrMax       = 0.80; // Continuation entries: max retracement fraction (beyond = too deep -> skip)

input group "Letra37 EA - 30-Min Trade Quality Protection"
input bool   InpQProtEnabled    = true;  // Enable 30-min quality protection rule (tightens SL when trade stalls)
input int    InpQProtMinutes    = 30;    // Age (minutes) without L1 hit -> activate protection mode
input int    InpQEscalMinutes   = 45;    // Age (minutes) without L1 hit -> escalation partial close
input double InpQProtSLFrac     = 0.25; // Protection SL = entry - this * initialRisk  (e.g. 0.25R closer)
input bool   InpQEscalHalf      = true;  // TRUE=close 50% at escalation, FALSE=close 100%
input int    InpDeathMinHoldBars = 6;   // Death entries: min bars held before ownership-transfer exit can fire (default 6=90min on M15; stops churn)

input group "Letra37 EA - Session & Signal Quality Filters"
input bool   InpBlockD4          = true;  // BLOCK D=4/4 entries (consensus = late entry, avg R=0.38, EV negative)
input bool   InpBlockD2London    = true;  // Block D=2/4 entries during London session 06-11 (require D=3+ - London open wicks tight SLs)
input bool   InpBlockD2Tuesday   = true;  // Block D=2/4 entries on Tuesdays (27% of SL hits, only 15% of winners)
input bool   InpBlockNewsWindow  = true;  // Block ALL entries during 14:45-15:30 server time (NFP/FOMC/CPI data window - 21% win rate)
input int    InpNewsHourStart    = 14;    // News window: start hour (server time)
input int    InpNewsMinStart     = 45;    // News window: start minute
input int    InpNewsHourEnd      = 15;    // News window: end hour
input int    InpNewsMinEnd       = 30;    // News window: end minute
input double InpBEAtrBuf         = 0.30; // Breakeven SL buffer for MOMENTUM trades (xATR). Old=1pt, now ~1-2 pts breathing room
input double InpBEAtrCampaign    = 0.50; // Breakeven SL buffer for CAMPAIGN trades (Asia/Close D=2/4 - wider: long slow builds wick deeper)
input int    InpCampaignProtMin  = 120;  // QProt: age threshold (minutes) for CAMPAIGN trades before protection fires (vs InpQProtMinutes for momentum)

//==================================================================
// EA GLOBALS
//==================================================================
CTrade        trade;
CPositionInfo posinfo;
CSymbolInfo   sym;
CAccountInfo  gAccount;

datetime gLastBarTime   = 0;
datetime gDayStamp      = 0;
int      gTradesToday   = 0;
string   gEntryBlock    = "-";   // live reason the EA is NOT entering (shown in panel)
double   gRecSizeMult   = 1.0;   // recursion-size-aware stop multiplier (set per entry from compression)
bool     gMktClosed     = false; // set when a management/flip order is rejected with 'Market closed' - stops the every-tick retry storm; reset each new bar (server SL/TP still protect the position)

//--- chart-TF rates for the engine ---
datetime eaT[]; double eaO[],eaH[],eaL[],eaC[],eaVol[];

//--- per-ticket management memory ---
// 5 partial-close levels (dollars profit): 900, 2300, 4400, 6400, 8600 -> 20% each
ulong  gMgTicket[]; double gMgInitSL[]; double gMgTP1[]; bool gMgPartialDone[]; bool gMgBEDone[]; int gMgDir[];
bool   gMgP1Done[];  // $900  -- 20% close + move SL to breakeven
bool   gMgP2Done[];  // $2300 -- 20% close
bool   gMgP3Done[];  // $4400 -- 20% close
bool   gMgP4Done[];  // $6400 -- 20% close
bool   gMgP5Done[];  // $8600 -- 20% close + activate trailing stop
bool   gMgTrailing[];// trailing stop active (after $8600 hit)
double gMgTrailSL[]; // last trailing SL price
//--- 30-min quality protection per-ticket state ---
datetime gMgEntryTime[];  // wall-clock time of entry (for minute-age)
double   gMgMFE[];        // max favorable excursion in R (updated every tick)
double   gMgMAE[];        // max adverse excursion in R  (updated every tick)
bool     gMgQProtMode[];  // protection mode active (30-min triggered)
bool     gMgQExit50[];    // escalation 50% partial already done (45-min)
bool     gMgIsDeathEntry[];// true = entry came from death fast-path (churn fix)
int      gMgTradeType[];   // 0=Campaign (Asia/Close D=2/4: patient multi-session), 1=Momentum (all others)

//==================================================================
// HELPERS
//==================================================================
int GradeRank(const string g)
{
   if(g=="A+") return(4); if(g=="A") return(3); if(g=="B") return(2); if(g=="C") return(1); return(0);
}
int MinGradeRank(const ENUM_MIN_GRADE g)
{
   switch(g){ case G_APLUS: return(4); case G_A: return(3); case G_B: return(2); case G_C: return(1); }
   return(0);
}
double NormPrice(const double p){ return(NormalizeDouble(p,_Digits)); }
double PointVal(){ return(_Point); }

double MinStopDist()
{
   double sl=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   double fr=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL)*_Point;
   return(MathMax(sl,fr));
}

double NormalizeLot(double lot)
{
   double minlot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxlot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step =SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) step=0.01;
   lot=MathFloor(lot/step)*step;
   if(lot<minlot) lot=minlot;
   if(lot>maxlot) lot=maxlot;
   double cap=(InpSmallAccount? MathMin(InpMaxLot,InpSmallAcctMaxLot) : InpMaxLot);
   if(lot>cap) lot=cap;
   return(lot);
}

double MoneyPerPointPerLot()
{
   double tickVal=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSize<=0) tickSize=_Point;
   return(tickVal*(_Point/tickSize));
}

double CalcLot(const double entry,const double sl)
{
   if(InpLotMode==LOT_FIXED) return(NormalizeLot(InpFixedLot));
   double riskPct=(InpSmallAccount? InpSmallAcctRiskPct : InpRiskPercent);   // small-account mode uses its own (lower) risk %
   double riskMoney=gAccount.Equity()*riskPct/100.0;
   double slPts=MathAbs(entry-sl)/_Point;
   double mpp=MoneyPerPointPerLot();
   if(slPts<1 || mpp<=0) return(NormalizeLot(InpFixedLot));
   double lot=riskMoney/(slPts*mpp);
   return(NormalizeLot(lot));                                 // NormalizeLot enforces broker min/step and the InpMaxLot cap
}

//--- ARC v2 apex builder (SYMPHONY port): uses the ARC inputs (declared in the EA section) and
//  the raw leg values published by ContextRun. apex = leg origin + dir*leg*ExtMult (the convex
//  curve target); ctx_arcNow is the time-projected expected price along the arc. ---
void ComputeARC()
{
   ctx_arcApex=NA; ctx_arcNow=NA; ctx_arcDir=0;
   int    wd =ctx_waveDir;
   double org=ctx_stop;        // leg origin = invalidation / protective extreme
   double ext=ctx_cExtreme;    // current leg extreme
   if(wd==0 || naf(org) || naf(ext)) return;
   double imp=MathAbs(ext-org);
   if(imp<=0.0) return;
   double apex=org + (double)wd*imp*InpArcExtMult;
   double t   =clamp(ctx_wp/100.0,0.0,1.0);
   ctx_arcApex=apex;
   ctx_arcNow =org + (apex-org)*MathPow(t,InpArcConvPower);
   ctx_arcDir =wd;
}

//--- management memory ---
int MgIndex(const ulong tk){ for(int q=0;q<ArraySize(gMgTicket);q++) if(gMgTicket[q]==tk) return(q); return(-1); }
void MgRegister(const ulong tk,const double initSL,const double tp1,const int dir,const bool isDeathEntry=false,const int tradeType=1)
{
   if(MgIndex(tk)>=0) return;
   int s=ArraySize(gMgTicket);
   ArrayResize(gMgTicket,s+1);ArrayResize(gMgInitSL,s+1);ArrayResize(gMgTP1,s+1);ArrayResize(gMgPartialDone,s+1);ArrayResize(gMgBEDone,s+1);ArrayResize(gMgDir,s+1);
   ArrayResize(gMgP1Done,s+1);ArrayResize(gMgP2Done,s+1);ArrayResize(gMgP3Done,s+1);ArrayResize(gMgP4Done,s+1);ArrayResize(gMgP5Done,s+1);
   ArrayResize(gMgTrailing,s+1);ArrayResize(gMgTrailSL,s+1);
   ArrayResize(gMgEntryTime,s+1);ArrayResize(gMgMFE,s+1);ArrayResize(gMgMAE,s+1);
   ArrayResize(gMgQProtMode,s+1);ArrayResize(gMgQExit50,s+1);ArrayResize(gMgIsDeathEntry,s+1);ArrayResize(gMgTradeType,s+1);
   gMgTicket[s]=tk; gMgInitSL[s]=initSL; gMgTP1[s]=tp1; gMgPartialDone[s]=false; gMgBEDone[s]=false; gMgDir[s]=dir;
   gMgP1Done[s]=false; gMgP2Done[s]=false; gMgP3Done[s]=false; gMgP4Done[s]=false; gMgP5Done[s]=false;
   gMgTrailing[s]=false; gMgTrailSL[s]=0.0;
   // quality protection initial state
   gMgEntryTime[s]=TimeCurrent(); gMgMFE[s]=0.0; gMgMAE[s]=0.0;
   gMgQProtMode[s]=false; gMgQExit50[s]=false;
   gMgIsDeathEntry[s]=isDeathEntry;
   gMgTradeType[s]=tradeType;
}
void MgCleanup()
{
   for(int q=ArraySize(gMgTicket)-1;q>=0;q--){
      if(!posinfo.SelectByTicket(gMgTicket[q])){
         ArrayRemove(gMgTicket,q,1);ArrayRemove(gMgInitSL,q,1);ArrayRemove(gMgTP1,q,1);ArrayRemove(gMgPartialDone,q,1);ArrayRemove(gMgBEDone,q,1);ArrayRemove(gMgDir,q,1);
         ArrayRemove(gMgP1Done,q,1);ArrayRemove(gMgP2Done,q,1);ArrayRemove(gMgP3Done,q,1);ArrayRemove(gMgP4Done,q,1);ArrayRemove(gMgP5Done,q,1);
         ArrayRemove(gMgTrailing,q,1);ArrayRemove(gMgTrailSL,q,1);
         ArrayRemove(gMgEntryTime,q,1);ArrayRemove(gMgMFE,q,1);ArrayRemove(gMgMAE,q,1);
         ArrayRemove(gMgQProtMode,q,1);ArrayRemove(gMgQExit50,q,1);
         ArrayRemove(gMgIsDeathEntry,q,1);ArrayRemove(gMgTradeType,q,1);
      }
   }
}

int CountOwnPositions()
{
   int n=0;
   for(int q=PositionsTotal()-1;q>=0;q--){
      ulong tk=PositionGetTicket(q);
      if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)==(long)InpMagic && PositionGetString(POSITION_SYMBOL)==_Symbol) n++;
   }
   return(n);
}
int OwnPositionDir()  // returns +1/-1 of first own position, 0 if none
{
   for(int q=PositionsTotal()-1;q>=0;q--){
      ulong tk=PositionGetTicket(q);
      if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)==(long)InpMagic && PositionGetString(POSITION_SYMBOL)==_Symbol)
         return(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1);
   }
   return(0);
}
bool OwnYoungerThan(const int bars)   // true if any own position has been open < bars
{
   int ps=MathMax(PeriodSeconds(_Period),1);
   for(int q=PositionsTotal()-1;q>=0;q--){
      ulong tk=PositionGetTicket(q);
      if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      int held=(int)((TimeCurrent()-(datetime)PositionGetInteger(POSITION_TIME))/ps);
      if(held<bars) return(true);
   }
   return(false);
}
void CloseOwnPositions(const int dirFilter=0) // dirFilter 0=all, 1=longs, -1=shorts
{
   for(int q=PositionsTotal()-1;q>=0;q--){
      ulong tk=PositionGetTicket(q);
      if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      int d=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      if(dirFilter!=0 && d!=dirFilter) continue;
      if(!trade.PositionClose(tk) && MktClosed()) return;   // market closed/disabled/close-only -> arm back-off, stop the every-tick retry storm
   }
}
void DeletePendingOrders()
{
   for(int q=OrdersTotal()-1;q>=0;q--){
      ulong tk=OrderGetTicket(q);
      if(tk==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)==(long)InpMagic && OrderGetString(ORDER_SYMBOL)==_Symbol)
         trade.OrderDelete(tk);
   }
}

//==================================================================
// OnInit
//==================================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviation);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);
   sym.Name(_Symbol);

   showOriginShort=(originMode==OM_SHORT||originMode==OM_BOTH);
   showOriginLong =(originMode==OM_LONG ||originMode==OM_BOTH);
   ResetState();
   g_lastProcessed=-1;

   gDayStamp=0; gTradesToday=0;
   gLastBarTime=0;

   //--- LIVE: startup summary so the running configuration is visible in the Experts log ---
   bool _live=!MQLInfoInteger(MQL_TESTER);
   PrintFormat("=== Letra37 EA init === %s  %s,%s  build=f72-ownership-engine-v1",
               (_live?"LIVE/DEMO":"STRATEGY TESTER"),_Symbol,EnumToString(_Period));
   PrintFormat("    RISK   : mode=%s  risk=%.2f%%  maxLot=%.2f  maxTrades/day=%d",
               (InpLotMode==LOT_RISK_PCT?"RISK%":"FIXED"),InpRiskPercent,InpMaxLot,InpMaxTradesPerDay);
   PrintFormat("    STOPS  : hardSL=ON (structure, minFloor %.1f ATR)  TP=NONE (ownership exits only)  trail=REMOVED  BE=REMOVED  partial=REMOVED",
               InpMinSLAtr);
   PrintFormat("    EXITS  : ownerTransfer=%s(%.0f%%)  termComplete=%s  p2Choch=%s(%d bars)  exhaustion=%s",
               (InpExitOnOwnerTransfer?"on":"off"),InpOwnerTransferThresh,
               (InpExitOnTermComplete?"on":"off"),
               (InpExitOnP2CHOCH?"on":"off"),InpP2CHOCHConfirmBars,
               (InpUseExhaustionExit?"on":"off"));
   PrintFormat("    SAFETY : verifyTradeAllowed=%s  retries=%d  marginBuffer=%.0f%%  spreadGuard=%s",
               (InpVerifyTradeAllowed?"on":"off"),InpOrderRetries,InpMarginBufferPct,
               (InpMaxSpreadPoints>0?IntegerToString(InpMaxSpreadPoints)+"pts":"OFF"));
   if(_live && InpMaxSpreadPoints<=0)
      Print("    WARNING: spread guard is OFF (InpMaxSpreadPoints=0). On live XAUUSD set it to reject news-spike spreads.");
   if(_live && (InpRiskPercent>2.0 || InpMaxLot>5.0))
      Print("    WARNING: risk settings are aggressive for live - confirm InpRiskPercent / InpMaxLot before running.");
   if(InpSmallAccount)
      PrintFormat("    SMALL-ACCT MODE ON: risk=%.2f%%  maxLot=%.2f  skipIfRisk>%.2f%%  maxTrades/day=%d",
                  InpSmallAcctRiskPct,InpSmallAcctMaxLot,InpSmallAcctMaxRiskPct,InpSmallAcctMaxTrades);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){ Comment(""); }

//==================================================================
// DAILY GUARD
//==================================================================
void DailyRollover()
{
   //--- SPEC AUDIT: daily loss halt REMOVED (external constraint, not curve logic).
   //  Retain only the daily trade counter reset for max-trades-per-day entry guard. ---
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   datetime dayKey=(datetime)(dt.year*10000+dt.mon*100+dt.day);
   if(dayKey!=gDayStamp){
      gDayStamp=dayKey; gTradesToday=0;
   }
}

bool SessionOK()
{
   if(!InpUseSession) return(true);
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(InpSkipFriday && dt.day_of_week==5) return(false);
   if(InpSessStartHour<=InpSessEndHour)
      return(dt.hour>=InpSessStartHour && dt.hour<InpSessEndHour);
   return(dt.hour>=InpSessStartHour || dt.hour<InpSessEndHour);
}

//==================================================================
// LIVE SAFETY HELPERS
//==================================================================
//--- is it currently safe to place a NEW order? (always true in the Strategy Tester) ---
bool TradingEnabled()
{
   if(MQLInfoInteger(MQL_TESTER)) return(true);                       // tester: never blocked
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))      return(false);   // no broker connection
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))  return(false);   // AutoTrading button off
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))            return(false);   // EA "Allow Algo Trading" off
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))    return(false);   // broker/account disallows trading
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))     return(false);   // broker disallows EAs
   return(true);
}
//--- would this order leave enough free margin? (and is the account's margin level safe?) ---
bool MarginOK(const int dir,const double lot,const double price)
{
   if(InpHaltOnLowMargin){
      double mlvl=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);            // 0 when no positions are open
      if(mlvl>0.0 && mlvl<200.0) return(false);                      // margin level below 200% -> too hot to add risk
   }
   double need=0.0;
   ENUM_ORDER_TYPE ot=(dir==1?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   if(!OrderCalcMargin(ot,_Symbol,lot,price,need)) return(true);     // can't compute -> don't block
   double freeM=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double buffer=1.0-clamp(InpMarginBufferPct,0.0,90.0)/100.0;       // e.g. 5% -> may use up to 95% of free margin
   return(need <= freeM*buffer);
}

//==================================================================
// ENGINE COMPUTE (full recompute over window each new bar)
//==================================================================
void ComputeEngine()
{
   int want=InpEngineBars;
   MqlRates r[]; ArraySetAsSeries(r,false);
   int got=CopyRates(_Symbol,_Period,0,want,r);
   if(got<=0) return;
   ArrayResize(eaT,got);ArrayResize(eaO,got);ArrayResize(eaH,got);ArrayResize(eaL,got);ArrayResize(eaC,got);ArrayResize(eaVol,got);
   for(int q=0;q<got;q++){ eaT[q]=r[q].time; eaO[q]=r[q].open; eaH[q]=r[q].high; eaL[q]=r[q].low; eaC[q]=r[q].close; eaVol[q]=(double)r[q].tick_volume; }
   int warmup=MathMax(2*structLen,2*pivotLen)+effLen+10;
   if(got<warmup+5) return;
   ResetState();
   EngineRun(got,eaT,eaO,eaH,eaL,eaC,eaVol,MathMax(warmup,got-InpEngineBars));
   if(InpUseV60Context) ContextRun(InpEngineBars);   // v60 context (does not alter Letra cur_* decision)
   ComputeARC();                                      // SYMPHONY ARC apex/value from the published leg
}

//==================================================================
// DECISION + ENTRY
//==================================================================
int DesiredDirection()
{
   bool engLong=cur_longSignal, engShort=cur_shortSignal;
   if(InpSignalSource==SIG_ENGINE) return(engLong?1:engShort?-1:0);
   // SIG_EITHER / SIG_BOTH / SIG_V72 -- arrow leads. DOE removed from entry chain.
   if(engLong)  return(1);
   if(engShort) return(-1);
   // OWNERSHIP DEATH PATH: when 2+ death signals confirmed AND macro direction is dying,
   // the counter-direction IS the signal even when no arrow or DOE fired.
   // Uses cur_dirH4/cur_dirH1 globals (available in DesiredDirection scope).
   if(cur_ownerDeathSignals >= 2){
      int _macD = (cur_dirH4!=0)?cur_dirH4:(cur_dirH1!=0)?cur_dirH1:0;
      if(_macD==-1 && cur_dirM5==1) return(1);   // H4 bearish dying, M5 bullish forming
      if(_macD==1  && cur_dirM5==-1) return(-1);  // H4 bullish dying, M5 bearish forming
   }
   return(0);
}

//--- dominant directional consensus.
//--- the DOMINANT thesis direction. The headline command narrative leads (it is what
//--- the panel literally prints, e.g. "Bullish reversal developing"); the DOE decision
//--- confirms; only if BOTH are neutral do we fall back to the structural consensus.
//--- The lagging stack/pressure/wave do NOT get to cancel a clear thesis (they stay
//--- bearish during a developing bullish reversal, which is exactly when we were
//--- wrongly selling). 0 = no clear thesis.
int ConsensusBias()
{
   //--- 1) command narrative = the headline thesis on the panel ---
   if(StringFind(cur_cmdNarrative,"invalidated")<0){
      if(StringFind(cur_cmdNarrative,"Bull")>=0) return(1);
      if(StringFind(cur_cmdNarrative,"Bear")>=0) return(-1);
   }
   //--- 2) DOE removed from ConsensusBias --- 
   //--- 3) fallback: structural consensus (network + wave + stack) ---
   int v=ctx_netBias+ctx_waveDir;
   if(ctx_stackDir>0) v+=1; else if(ctx_stackDir<0) v-=1;
   if(v>0) return(1);
   if(v<0) return(-1);
   return(0);
}

bool PassesFilters(const int dir)
{
   if(dir==1 && !InpTradeLongs){ gEntryBlock="longs off"; return(false); }
   if(dir==-1&& !InpTradeShorts){ gEntryBlock="shorts off"; return(false); }
   if(cur_invInvalidated){ gEntryBlock="invalidated"; return(false); }
   // ERF gate, grade, DOE confidence, opp score REMOVED -- ownership death engine is the authority
   if(InpRequireHtfAlign && !(cur_htfAlign==dir || cur_htfAlign==0)){ gEntryBlock="HTF align"; return(false); }
   if(InpUseV60Context){
      if(InpReqNetAgree   && !(ctx_netBias==dir || ctx_netBias==0)){ gEntryBlock="network disagrees"; return(false); }
      if(InpReqStackAgree && ctx_stackDir!=dir){ gEntryBlock="stack disagrees"; return(false); }
      if(InpReqCurveAlive && ctx_life<InpCurveAliveMin){ gEntryBlock="curve weak"; return(false); }
      if(InpReqNarrative  && ctx_narrState=="WEAKENING"){ gEntryBlock="narrative weak"; return(false); }
      if(InpReqTimeAlign  && ctx_timeAlign<InpMinTimeAlign){ gEntryBlock="time align low"; return(false); }
      if(InpBlockV60Terminal && (ctx_phase=="Liquidation"||ctx_phase=="Terminal Curve") && ctx_waveDir!=0 && ctx_waveDir!=dir){ gEntryBlock="v60 terminal vs dir"; return(false); }
      if(InpTIEBlockOpposed && ctx_timeAlign>=InpTIEStrongAlign && ctx_timeDir!=0 && ctx_timeDir!=dir){ gEntryBlock="TIE opposed"; return(false); }
   }
   return(true);
}

//--- recursion-size-aware multipliers (Part 4a): compression sets loop size, so a
//--- failure-swing/compressed terminal gets a TIGHTER stop + earlier partial, while a
//--- wide low-compression curve gets a WIDER stop + full target. Geometry, not guesswork.
double RecSizeMult()
{
   if(!InpCompSizing || !InpUseV60Context) return(1.0);
   string r=cur_compRegime;
   return( r=="Extreme"?0.65 : r=="High"?0.80 : r=="Medium"?1.0 : 1.25 );  // Low compression = wide loops
}
//--- SPEC AUDIT: PartialFrac() removed (partial close logic deleted -- campaigns run to completion).

//--- protective stop just beyond the recent KEY swing high/low (real structure).
//--- long  -> below the lowest low of the last InpSwingLookback closed bars
//--- short -> above the highest high of the last InpSwingLookback closed bars
//--- returns 0.0 when disabled or unavailable.
double KeyLevelStop(const int dir,const double entry)
{
   if(!InpUseKeyLevelStop) return(0.0);
   double atr=cur_atr; if(atr<=0) atr=10*_Point;
   int lb=InpSwingLookback; if(lb<2) lb=2;
   double buf=InpKeyLevelBufATR*atr*gRecSizeMult;
   double s=0.0;
   if(dir==1){
      int idx=iLowest(_Symbol,_Period,MODE_LOW,lb,1);     // 1 = skip the still-forming bar
      if(idx>=0){ double lo=iLow(_Symbol,_Period,idx); if(lo>0) s=lo-buf; }
      //--- fold in the engine's structural invalidation (take whichever protects more = lower) ---
      if(!naf(cur_invActiveStop) && cur_invActiveStop<entry){ double e=cur_invActiveStop-buf; if(s==0.0 || e<s) s=e; }
      return( s<entry ? s : 0.0 );                        // must sit below entry to be valid
   } else {
      int idx=iHighest(_Symbol,_Period,MODE_HIGH,lb,1);
      if(idx>=0){ double hi=iHigh(_Symbol,_Period,idx); if(hi>0) s=hi+buf; }
      if(!naf(cur_invActiveStop) && cur_invActiveStop>entry){ double e=cur_invActiveStop+buf; if(s==0.0 || e>s) s=e; }
      return( s>entry ? s : 0.0 );                        // must sit above entry to be valid
   }
}

double ComputeSL(const int dir,const double entry)
{
   double atr=cur_atr; if(atr<=0) atr=10*_Point;
   double sl;
   if(InpSLMode==SL_ENGINE && !naf(cur_invActiveStop)){
      sl=cur_invActiveStop + (dir==1? -atr*InpSLEngineBufATR : atr*InpSLEngineBufATR);
   } else if(InpSLMode==SL_FIXED){
      sl=entry + (dir==1? -InpSLFixedPoints*_Point : InpSLFixedPoints*_Point);
   } else {
      sl=entry + (dir==1? -atr*InpSLAtrMult : atr*InpSLAtrMult);
   }
   //--- push the stop BEYOND the recent key swing high/low so structure protects it ---
   double ks=KeyLevelStop(dir,entry);
   if(ks!=0.0){
      if(dir==1)  sl=MathMin(sl,ks);   // long: take the lower (more protective) stop
      else        sl=MathMax(sl,ks);   // short: take the higher (more protective) stop
   }
   //--- enforce correct side + minimum stop distance (broker min AND >= InpMinSLAtr*ATR) ---
   double minD=MathMax(MinStopDist()+_Point, InpMinSLAtr*gRecSizeMult*atr);
   if(dir==1  && sl>entry-minD) sl=entry-minD;
   if(dir==-1 && sl<entry+minD) sl=entry+minD;
   //--- safety cap so a runaway swing can't create an absurd stop ---
   double maxD=InpMaxSLAtr*atr;
   if(dir==1  && sl<entry-maxD) sl=entry-maxD;
   if(dir==-1 && sl>entry+maxD) sl=entry+maxD;
   return(NormPrice(sl));
}

//--- SYMPHONY-style STOP: the stop sits JUST beyond the ONE level whose break invalidates the
//  trade = the curve's origin / anchor. We pick a SINGLE coherent level by priority (the level
//  the entry keys off), side-validate it (so a wrong-side level can never be used - the old
//  reversal bug), buffer it by a small ATR amount, and set it once. The recent swing is only a
//  fallback when no origin level exists. ATR safety cap always applies.
double ComputeStructureSL(const int dir,const double entry,const bool fuEntry,const bool mtfEntry)
{
   double a=cur_atr; if(a<=0) a=10*_Point;
   double buf=InpAnchorBufATR*a*gRecSizeMult;
   double lvl=NA;
   if(InpStructureStop){
      if(mtfEntry && !naf(cur_mtfEntryInv))                                    lvl=cur_mtfEntryInv;   // owning rung invalidation (leg origin)
      else if(fuEntry && InpUseV60Context && !naf(ctx_fuTip))                  lvl=ctx_fuTip;         // FU wick extreme (curve origin)
      else if(InpUseV60Context && ctx_atTrueInduction && !naf(ctx_lowestFlip)) lvl=ctx_lowestFlip;    // true S/D (lowest flip)
      else if(!naf(cur_invActiveStop))                                         lvl=cur_invActiveStop; // engine structural invalidation
      //--- side-validate: a level on the WRONG side of entry is discarded (never jam to min-dist) ---
      if(!naf(lvl) && ((dir==1 && lvl>=entry) || (dir==-1 && lvl<=entry))) lvl=NA;
   }
   double sl;
   if(!naf(lvl)) sl=lvl + (dir==1? -buf : buf);                                // stop JUST beyond the invalidation/origin
   else {
      double ks=KeyLevelStop(dir,entry);                                       // fallback: recent swing (side-safe), else engine/ATR
      sl=(ks!=0.0)? ks : ComputeSL(dir,entry);
   }
   //--- minimum distance: broker-min AND a sane ATR floor. A structure level that sits CLOSER
   //  than this means the entry is basically ON the level - a sub-ATR stop there just gets
   //  picked off by normal gold-wick noise within a bar or two (the "opens and closes straight
   //  away" bug), and the tiny risk also drags the RR-scaled TP into noise range. So the stop is
   //  floored at InpMinSLAtr*ATR. gRecSizeMult lets a compressed/volatile curve run tighter
   //  (~1 ATR in Extreme) while a wide curve gets ~1.9 ATR. The structure level is still used
   //  whenever it sits FURTHER than this floor (the common case). ---
   double minD=MathMax(MinStopDist()+_Point, InpMinSLAtr*gRecSizeMult*a);
   if(dir==1  && sl>entry-minD) sl=entry-minD;
   if(dir==-1 && sl<entry+minD) sl=entry+minD;
   //--- ATR safety cap ---
   double maxD=InpMaxSLAtr*a;
   if(dir==1  && sl<entry-maxD) sl=entry-maxD;
   if(dir==-1 && sl>entry+maxD) sl=entry+maxD;
   return(NormPrice(sl));
}

double ComputeTP(const int dir,const double entry,const double sl)
{
   //--- SPEC AUDIT: ALL take-profit targets removed. Campaigns complete on ownership transfer /
   //  terminal-sequence completion / P2 CHOCH -- not on an arbitrary RR or price level.
   //  Return 0 = no broker-side TP (the position lives until the engine closes it or SL hits). ---
   return(0.0);
}

//--- SYMPHONY ENTRY MECHANISM (ported): the precise "WHEN". On the closed chart bar, require a
//  momentum-delta inflection INTO the trade direction (the turn), at a measured retracement
//  depth for continuation entries, with the inducement complete (not still inside the manip
//  band). This converts F16's STATE-based entry into an EVENT-based one that lands on the curve.
//  F16's context (entry-cycle gate) already decided WHETHER; this decides exactly WHEN. ---
bool SymphonyTrigger(const int dir)
{
   if(!InpUseSymphonyTrigger) return(true);
   int nb=(int)ArraySize(eaC);
   if(nb<4) return(true);                              // not enough closed bars -> don't block (startup only)
   int last=nb-2;                                      // last CLOSED chart bar
   double d1=eaC[last]-eaC[last-1];                    // most-recent closed-bar delta
   double d2=eaC[last-1]-eaC[last-2];                  // the delta before it
   //--- 1) momentum inflection INTO the trade direction = the turn bar ---
   if(InpRequireMomFlip)
   {
      bool flip=(dir==1)? (d1>=0.0 && d2<0.0) : (d1<=0.0 && d2>0.0);
      if(!flip){ gEntryBlock="awaiting momentum flip (on-curve turn)"; return(false); }
   }
   //--- 2) retracement band - CONTINUATION entries only (dir == live wave). Reversal/terminal
   //       location is already handled by the at-flip + shift gate. ctx_retrX: 0 at the leg
   //       extreme, 100 back at the invalidation/origin. ---
   if(InpUseV60Context && ctx_waveDir==dir)
   {
      double r=ctx_retrX/100.0;
      if(r<InpEntryRetrMin || r>InpEntryRetrMax)
      { gEntryBlock="retrace "+DoubleToString(r,2)+" out of band ["+DoubleToString(InpEntryRetrMin,2)+"-"+DoubleToString(InpEntryRetrMax,2)+"]"; return(false); }
   }
   //--- 3) inducement complete: never enter while still inside the manipulation band ---
   if(InpUseV60Context && ctx_inManipBand && !ctx_atTrueInduction)
   { gEntryBlock="inducement not complete (in manip band)"; return(false); }
   return(true);
}

void TryEnter()
{
   int dir=DesiredDirection();
   bool aggressive=false, fuEntry=false, mtfEntry=false;
   // ================================================================
   // DEATH PATH -- HIGHEST PRIORITY. Checked before ANY other logic.
   // When 2+ death signals confirmed, direction is set immediately.
   // Macro curve dying -> trade the opposing direction. No prerequisites.
   // ================================================================
   if(cur_ownerDeathSignals >= 2){
      int _macDeath = (cur_dirH4!=0)?cur_dirH4:(cur_dirH1!=0)?cur_dirH1:0;
      if(_macDeath != 0 && dir==0) dir = -_macDeath;  // dying macro -> oppose it
      // death fast-path: go straight to order, skip all intermediate gates
      if(_macDeath != 0){
         // -- SIGNAL QUALITY + SESSION GATES (from deep audit) ----------
         // These filters remove the statistically confirmed loss clusters:
         // D=4/4 (EV negative), London D=2/4 (20-29% win), Tuesday D=2/4 (0.56:1),
         // and the 14:45-15:30 news window (21% win, 10% of all hard SL).
         MqlDateTime _dte; TimeToStruct(TimeCurrent(),_dte);
         int _eh=_dte.hour, _em=_dte.min, _wd=_dte.day_of_week;
         bool _isLondon =(_eh>=6 && _eh<=11);
         bool _isTuesday=(_wd==2);
         bool _isNews   =InpBlockNewsWindow && ((_eh==InpNewsHourStart && _em>=InpNewsMinStart)||(_eh==InpNewsHourEnd && _em<=InpNewsMinEnd));
         bool _isAsia   =(_eh>=0 && _eh<=5);
         bool _isClose  =(_eh>=18);
         // Block D=4/4 (consensus = late, avg R=0.38, EV<0)
         if(InpBlockD4 && cur_ownerDeathSignals>=4){ gEntryBlock="D=4/4 blocked (late consensus)"; return; }
         // Block D=2/4 during London open (20-29% win rate, wicks tight SLs)
         if(InpBlockD2London && _isLondon && cur_ownerDeathSignals<=2){ gEntryBlock="D=2/4 blocked in London session"; return; }
         // Block D=2/4 on Tuesdays (27% SL hits vs 15% winners)
         if(InpBlockD2Tuesday && _isTuesday && cur_ownerDeathSignals<=2){ gEntryBlock="D=2/4 blocked on Tuesday"; return; }
         // Block news window 14:45-15:30 (data releases blow through tight SLs)
         if(_isNews){ gEntryBlock="news window blocked ("+IntegerToString(_eh)+":"+IntegerToString(_em)+")"; return; }

         // -- TRADE TYPE CLASSIFICATION (drives BE SL width + QProt threshold) --
         // Campaign (type 0): Asia/Close D=2/4 -- slow multi-session hold, needs wide BE
         // Momentum (type 1): all other confirmed entries -- session move, tighter mgmt
         int _tradeType = ((_isAsia || _isClose) && cur_ownerDeathSignals==2) ? 0 : 1;

         if(dir==1 && !InpTradeLongs){ gEntryBlock="longs off"; return; }
         if(dir==-1 && !InpTradeShorts){ gEntryBlock="shorts off"; return; }
         if(cur_invInvalidated){ gEntryBlock="invalidated"; return; }
         if(!SessionOK()){ gEntryBlock="session closed"; return; }
         int _maxT2=(InpSmallAccount&&InpSmallAcctMaxTrades>0)?(InpMaxTradesPerDay>0?MathMin(InpMaxTradesPerDay,InpSmallAcctMaxTrades):InpSmallAcctMaxTrades):InpMaxTradesPerDay;
         if(_maxT2>0 && gTradesToday>=_maxT2){ gEntryBlock="max trades/day"; return; }
         if(InpMaxSpreadPoints>0){ long sp=(long)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD); if(sp>InpMaxSpreadPoints){ gEntryBlock="spread "+IntegerToString((int)sp); return; } }
         int ownD=OwnPositionDir();
         if(ownD!=0 && ownD!=dir){
            if(OwnYoungerThan(InpMinHoldBars)){ gEntryBlock="hold (young pos)"; return; }
            if(InpReverseOnOpposite){ CloseOwnPositions(0); DeletePendingOrders(); }
            else { gEntryBlock="opposite pos open"; return; }
         }
         if(CountOwnPositions()>=InpMaxPositions){ gEntryBlock="max positions"; return; }
         if(InpVerifyTradeAllowed && !TradingEnabled()){ gEntryBlock="algo-trading disabled"; return; }
         sym.RefreshRates();
         double askD=sym.Ask(), bidD=sym.Bid();
         double entryD=(dir==1?askD:bidD);
         gRecSizeMult=RecSizeMult();
         double slD=ComputeStructureSL(dir,entryD,false,false);
         double lotD=CalcLot(entryD,slD);
         if(!MarginOK(dir,lotD,entryD)){ gEntryBlock="insufficient margin"; return; }
         string _typeTx=(_tradeType==0?"CAMP":"MOM");
         string cmtD=InpComment+" DEATH"+IntegerToString(cur_ownerDeathSignals)+" "+_typeTx;
         bool okD=(dir==1)?trade.Buy(lotD,_Symbol,askD,slD,0.0,cmtD):trade.Sell(lotD,_Symbol,bidD,slD,0.0,cmtD);
         if(!okD && MktClosed()) return;
         MgRegister(trade.ResultOrder(),slD,NA,dir,true,_tradeType);
         gTradesToday++; gEntryBlock="ENTERED DEATH"+IntegerToString(cur_ownerDeathSignals)+" "+_typeTx;
         if(InpDebugEntries) Print("=== ENTRY DEATH ",(dir==1?"BUY":"SELL")," D=",cur_ownerDeathSignals,"/4 type=",_typeTx," @",DoubleToString(entryD,_Digits)," SL=",DoubleToString(slD,_Digits));
         return;
      }
   }
   //--- NORMAL PATHS (FU / MTF / aggressive / arrow) ---
   if(dir==0 && InpUseV60Context && InpFUExtremeEntry && ctx_fuFresh && ctx_fuDir!=0){
      int cb=ConsensusBias();
      if(InpFURequireBias && cb!=0 && ctx_fuDir!=cb){
         gEntryBlock="FU "+(ctx_fuDir==1?"buy":"sell")+" node opposes "+(cb==1?"bull":"bear")+" bias";
      } else {
         dir=ctx_fuDir; aggressive=true; fuEntry=true;
      }
   }
   //--- MULTI-TF: a fresh Demand/Supply Return on ANY rung (M1..H4) -- the EA sees every timeframe ---
   //  Only a genuine ENTRY CYCLE (dominance transferred to the recursive wave) qualifies;
   //  a first strike (low dominance) is skipped -- the curve is still building.
   if(dir==0 && InpMultiTFEntry && cur_mtfEntryFresh && cur_mtfEntryDir!=0 && cur_mtfEntryWt>=InpMinEntryRung){
      bool _ctx=InpUseV60Context;
      bool _okManip = (!InpAvoidManipBand || !_ctx || !ctx_inManipBand || ctx_atTrueInduction);
      bool _okTrue  = (!InpRequireTrueInduction || !_ctx || ctx_atTrueInduction);
      bool _okFlip  = (!InpRequireAtFlip || !_ctx || ctx_atFlip);
      bool _okShift = (InpMinTermShifts<=0 || !_ctx || !ctx_atFlip || ctx_termShifts>=InpMinTermShifts || ctx_failureSwing);
      bool _okOwner = (!InpOwnerMustAgree || !_ctx || cur_ownerDir==0 || cur_mtfEntryDir==cur_ownerDir
                       || cur_mtfEntryDom>=InpMinDomTransfer);   // a Return whose dominance has TRANSFERRED is the new curve -> trade the reversal (don't block it)
      if(cur_mtfEntryDom>=InpMinDomTransfer && cur_entryProb>=InpMinEntryProb && _okFlip && _okShift && _okManip && _okTrue && _okOwner){ dir=cur_mtfEntryDir; aggressive=true; mtfEntry=true; }
      else if(cur_mtfEntryDom<InpMinDomTransfer) gEntryBlock="first strike "+cur_mtfEntryTF+" (dom "+IntegerToString((int)cur_mtfEntryDom)+"% < entry cycle)";
      else if(!_okOwner) gEntryBlock=(cur_mtfEntryDir==1?"long":"short")+" vs owner "+cur_curveOwner+" "+(cur_ownerDir==1?"bull":"bear");
      else if(!_okManip) gEntryBlock="manipulation band (0.618-0.786, awaiting true flip)";
      else if(!_okTrue)  gEntryBlock="not at true induction (lowest flip)";
      else if(!_okFlip)  gEntryBlock="not at flip zone ("+DoubleToString(ctx_distFlipAtr,1)+"ATR away)";
      else if(!_okShift) gEntryBlock="terminal building "+IntegerToString(ctx_termShifts)+"/"+IntegerToString(InpMinTermShifts)+" shifts";
      else gEntryBlock="entry prob low "+IntegerToString((int)cur_entryProb)+"%";
   }
   //--- aggressive v60-confluence entry when strict Letra has no signal ---
   if(dir==0 && InpUseV60Context && InpAggressiveEntry){
      int adir=ctx_waveDir;
      bool ok = adir!=0
             && (!InpAggReqNet || ctx_netBias==adir || ctx_netBias==0)
             && ctx_life>=InpCurveAliveMin
             && !((ctx_phase=="Liquidation"||ctx_phase=="Terminal Curve") && ctx_waveDir!=adir)
             && !(InpAggReqTime && InpTIEBlockOpposed && ctx_timeAlign>=InpTIEStrongAlign && ctx_timeDir!=0 && ctx_timeDir!=adir);
      if(ok){ dir=adir; aggressive=true; }
   }
   if(dir==0){ gEntryBlock=(InpUseV60Context&&InpAggressiveEntry)?"no signal / v60 not aligned":"no signal (awaiting Return)"; return; }

   // (death fast-path already handled at top of TryEnter -- reaches here only for normal paths)
   //--- F72 entry-cycle context (computed ONCE, drives the vetoes + the gate below) --------
   bool _ctxOn=InpUseV60Context;
   bool _fast=(InpFastEntryOnComp && (cur_compRegime=="Extreme" || (_ctxOn && ctx_failureSwing)));
   int  _shiftsNow=(_ctxOn?ctx_termShifts:0);
   bool _atFlipNow=(_ctxOn?ctx_atFlip:(cur_distFlipAtr<=1.0));
   bool _shiftsOK=(_shiftsNow>=InpMinTermShifts) || _fast;
   bool _freshRet=(cur_mtfEntryFresh && cur_mtfEntryDom>=InpMinDomTransfer);
   //  TERMINAL entry = the NEW curve has taken control (dominance transferred / Entry Active /
   //  at the flip with the shift sequence done / failure-swing). At that point we are MEANT to
   //  trade the NEW curve even though the OLD owner/consensus still reads the prior direction -
   //  that reversal IS the trade, so it must NOT be vetoed.
   bool _terminalEntry = (cur_entryReady=="Entry Active") || _freshRet
                      || (_atFlipNow && _shiftsOK) || _fast || (_ctxOn && ctx_termComplete)
                      || (cur_ownerDeathSignals >= 2);  // ownership death = terminal entry confirmed
   //  WITH-CURVE = aligned with the live owning curve (continuation - riding the dominant move).
   bool _withCurve = (cur_ownerDir!=0 && dir==cur_ownerDir);

   //--- counter-bias veto: blocks RANDOM counter-trend trades, but NEVER a confirmed terminal
   //--- entry-cycle (that is exactly when we trade the new curve against the old consensus). ---

   //--- FLIP CONTEXT GATE (applies to ALL entry paths including FU/MTF/aggressive) ---
   //  Ported from V60: ALL curves have a flip zone. BUYS below, SELLS above.
   //  Use HTF authority ONLY (M15/H1/H4) -- M1/M3 zones are noise and flicker constantly.
   //  The highest available HTF flip zone defines macro buy/sell territory.
   {
      double _bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double _atrGate=cur_atr>0?cur_atr:10*_Point;
      // Check HTF flip zones in priority order: H4 > H1 > M15 > M5 (skip M1/M3 noise)
      double _htfFlipMid=NA;
      if(!naf(cur_cv_flipMid[5]))      _htfFlipMid=cur_cv_flipMid[5];  // H4
      else if(!naf(cur_cv_flipMid[4])) _htfFlipMid=cur_cv_flipMid[4];  // H1
      else if(!naf(cur_cv_flipMid[3])) _htfFlipMid=cur_cv_flipMid[3];  // M15
      else if(!naf(cur_cv_flipMid[2])) _htfFlipMid=cur_cv_flipMid[2];  // M5
      if(naf(_htfFlipMid)) _htfFlipMid=cur_ctxFlipMid;  // fallback
      // Apply the universal rule: buys below flip, sells above flip
      if(!naf(_htfFlipMid)){
         if(dir==1 && _bid>_htfFlipMid+_atrGate*0.3){ gEntryBlock="buy ABOVE HTF flip zone (sell territory)"; return; }
         if(dir==-1 && _bid<_htfFlipMid-_atrGate*0.3){ gEntryBlock="sell BELOW HTF flip zone (buy territory)"; return; }
      }
   }

   if(InpBlockCounterBias && !_terminalEntry){
      int cb=ConsensusBias();
      if(cb!=0 && dir!=cb){ gEntryBlock=(dir==1?"long":"short")+" vetoed vs "+(cb==1?"BULL":"BEAR")+" thesis"; return; }
   }
   //--- F72 UNIFIED ENTRY-CYCLE GATE -- trade WITH the curve -------------------------------
   //  Allow the entry when it is either (a) aligned with the live OWNER curve (continuation),
   //  or (b) a confirmed TERMINAL reversal where the new wave has taken control. Only a
   //  counter-trend, mid-build entry (neither of those) is blocked. A trigger (arrow / DOE /
   //  FU / fresh Return) is still required to reach here, so this does not over-trade.
   if(InpRequireEntryCycle){
      bool _cycleOK = _withCurve || _terminalEntry;
      if(!_cycleOK){ gEntryBlock="against curve / not entry-cycle (owner "+cur_curveOwner+" "+(cur_ownerDir==1?"bull":cur_ownerDir==-1?"bear":"flat")+", ready "+cur_entryReady+", shifts "+IntegerToString(_shiftsNow)+"/"+IntegerToString(InpMinTermShifts)+")"; return; }
   }
   //--- SYMPHONY precise trigger: enter on the TURN (closed-bar momentum inflection at the right
   //  retrace depth, inducement complete) - the "exactly WHEN" on top of the context "WHETHER". ---
   if(!SymphonyTrigger(dir)) return;
   if(!aggressive){
      if(!PassesFilters(dir)) return;          // strict Letra path keeps full filters
   } else {
      if(dir==1 && !InpTradeLongs){ gEntryBlock="longs off"; return; }     // aggressive path: light gating only
      if(dir==-1&& !InpTradeShorts){ gEntryBlock="shorts off"; return; }
      if(cur_invInvalidated){ gEntryBlock="invalidated"; return; }
   }
   if(!SessionOK()){ gEntryBlock="session closed"; return; }
   int _maxTrades=(InpSmallAccount && InpSmallAcctMaxTrades>0)
                  ? (InpMaxTradesPerDay>0? MathMin(InpMaxTradesPerDay,InpSmallAcctMaxTrades) : InpSmallAcctMaxTrades)
                  : InpMaxTradesPerDay;
   if(_maxTrades>0 && gTradesToday>=_maxTrades){ gEntryBlock="max trades/day"; return; }
   if(InpMaxSpreadPoints>0){ long sp=(long)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD); if(sp>InpMaxSpreadPoints){ gEntryBlock="spread "+IntegerToString((int)sp); return; } }

   int ownDir=OwnPositionDir();
   if(ownDir!=0 && ownDir!=dir){
      if(OwnYoungerThan(InpMinHoldBars)){ gEntryBlock="hold (young pos, no flip)"; return; }   // don't flip a fresh trade
      if(InpReverseOnOpposite){ if(InpDebugExits) Print("=== FLIP  closing ",(ownDir==1?"BUY":"SELL")," to reverse into ",(dir==1?"BUY":"SELL"),"  (owner ",cur_curveOwner," ",f_waveDirLabel(cur_ownerDir),", thesis ",(ConsensusBias()==1?"BULL":ConsensusBias()==-1?"BEAR":"neutral"),")"); CloseOwnPositions(0); DeletePendingOrders(); }
      else { gEntryBlock="opposite pos open"; return; }
   }
   if(CountOwnPositions()>=InpMaxPositions){ gEntryBlock="max positions"; return; }
   if(gMktClosed){ gEntryBlock="market closed (flip-close rejected)"; return; }   // a flip/opposite close was rejected because the market is shut -> do NOT open a fresh leg now
   if(InpVerifyTradeAllowed && !TradingEnabled()){ gEntryBlock="algo-trading disabled / terminal not connected"; return; }

   sym.RefreshRates();
   double ask=sym.Ask(), bid=sym.Bid();
   double entry=(dir==1?ask:bid);
   gRecSizeMult=RecSizeMult();          // recursion-size-aware stop sizing (compression -> loop size)
   double slBase=ComputeStructureSL(dir,entry,fuEntry,mtfEntry);   // F72: stop BEYOND the actual structure price is reacting off
   double lot=CalcLot(entry,slBase);
   double tp=ComputeTP(dir,entry,slBase);
   //--- LIVE: don't send an order the account can't safely afford ---
   if(!MarginOK(dir,lot,entry)){ gEntryBlock="insufficient free margin / margin level unsafe"; return; }
   //--- SMALL ACCOUNT: the broker minimum lot may force more risk than allowed (can't size smaller) -> skip ---
   if(InpSmallAccount && InpSmallAcctMaxRiskPct>0.0){
      double _riskMoney=(MathAbs(entry-slBase)/_Point)*MoneyPerPointPerLot()*lot;
      double _riskPctActual=_riskMoney/MathMax(gAccount.Equity(),1.0)*100.0;
      if(_riskPctActual>InpSmallAcctMaxRiskPct){ gEntryBlock="small-acct: min-lot risk "+DoubleToString(_riskPctActual,2)+"% > cap "+DoubleToString(InpSmallAcctMaxRiskPct,2)+"%"; return; }
   }
   bool _arrow=(dir==1?cur_longSignal:cur_shortSignal);
   string _trig=fuEntry?"FU":mtfEntry?("MTF:"+cur_mtfEntryTF):aggressive?"V60AGG":_arrow?"ARROW":"DEATH";
   string cmt=InpComment+" "+_trig+(cur_ownerDeathSignals>0?" D"+IntegerToString(cur_ownerDeathSignals):"");

   bool ok=false;
   if(InpUseLimitEntry && !naf(cur_doeEntryMid)){
      double lim=NormPrice(cur_doeEntryMid);
      double slL=ComputeStructureSL(dir,lim,fuEntry,mtfEntry);
      double tpL=ComputeTP(dir,lim,slL);
      double lotL=CalcLot(lim,slL);
      datetime exp=(InpPendingExpiryBars>0)?(TimeCurrent()+(datetime)(InpPendingExpiryBars*PeriodSeconds(_Period))):0;
      ENUM_ORDER_TYPE_TIME tt=(exp>0?ORDER_TIME_SPECIFIED:ORDER_TIME_GTC);
      trade.SetTypeFillingBySymbol(_Symbol);
      if(dir==1) ok=trade.BuyLimit(lotL,lim,_Symbol,slL,tpL,tt,exp,cmt);
      else       ok=trade.SellLimit(lotL,lim,_Symbol,slL,tpL,tt,exp,cmt);
   } else {
      //--- LIVE: market send with retry on TRANSIENT broker errors (requote / price changed /
      //  off-quotes / timeout). Re-quote the price each attempt. Non-transient errors stop the loop. ---
      int _tries=MathMax(1,InpOrderRetries);
      for(int _a=0;_a<_tries && !ok;_a++){
         sym.RefreshRates();
         double _ask=sym.Ask(), _bid=sym.Bid();
         ok=(dir==1)? trade.Buy(lot,_Symbol,_ask,slBase,tp,cmt)
                    : trade.Sell(lot,_Symbol,_bid,slBase,tp,cmt);
         if(ok) break;
         uint _rc=trade.ResultRetcode();
         bool _transient=(_rc==TRADE_RETCODE_REQUOTE||_rc==TRADE_RETCODE_PRICE_CHANGED||
                          _rc==TRADE_RETCODE_PRICE_OFF||_rc==TRADE_RETCODE_TIMEOUT);
         if(!_transient) break;                       // hard error -> stop (MktClosed() handles the closed-market case below)
         if(InpRetryWaitMs>0 && !MQLInfoInteger(MQL_TESTER)) Sleep(InpRetryWaitMs);
      }
   }
   if(!ok) MktClosed();   // if the entry was rejected because the market is shut, arm the back-off so the same-tick ManagePositions() does not also hammer the broker
   if(ok){
      gTradesToday++;
      gEntryBlock="ENTERED "+_trig;
      //--- DEBUG: full entry reasoning so we can map where it needs improving ---
      if(InpDebugEntries){
         double _risk=MathAbs(entry-slBase); double _rr=_risk>0?MathAbs(tp-entry)/_risk:0.0;
         int _cb=ConsensusBias();
         Print("=== ENTRY ",(dir==1?"BUY":"SELL")," src=",_trig,
               "  @",DoubleToString(entry,_Digits)," SL=",DoubleToString(slBase,_Digits)," TP=",DoubleToString(tp,_Digits),
               " lot=",DoubleToString(lot,2)," RR=",DoubleToString(_rr,2)," SLpts=",DoubleToString(_risk/_Point,0));
         Print("    TRIGGER : arrow=",(_arrow?"Y":"n")," DOE=",cur_doeAction," FU=",(fuEntry?"Y":"n"),
               " MTF=",(mtfEntry?cur_mtfEntryTF+" dom"+DoubleToString(cur_mtfEntryDom,0)+"%":"n"),
               " aggr=",(aggressive?"Y":"n"));
         Print("    OWNER   : ",cur_curveOwner," ",(cur_ownerDir==1?"Bull":cur_ownerDir==-1?"Bear":"Flat"),
               "  trans=",cur_transState,"  camp=",ctx_campaign,"  atFlip=",(ctx_atFlip?"Y":"n"),"  ready=",cur_entryReady);
         Print("    RECUR   : dom=",DoubleToString(cur_domTransfer,0),"%  comp=",cur_compRegime,
               "  depth=",cur_recDepth,"/",cur_expRecDepth,"  budget=",DoubleToString(cur_curveBudget,0),"%  toFlip=",DoubleToString(cur_distFlipAtr,1),"ATR  entryP=",DoubleToString(cur_entryProb,0),"%");
         Print("    TERMINAL: shifts=",ctx_termShifts,"/",ctx_termExpected,"  m1=",ctx_termM1Cycles,"  done=",(ctx_termComplete?"Y":"n"),
               "  induction=",(ctx_atTrueInduction?"TRUE":"-"),"  manip=",(ctx_inManipBand?"Y":"n"),"  failSwing=",(ctx_failureSwing?"Y":"n"),"  fuMerged=",(ctx_fuMerged?"Y":"n"));
         Print("    THESIS  : ",(_cb==1?"BULL":_cb==-1?"BEAR":"neutral"),"  net=",cur_dirM5==0?0:cur_dirM5,"  narr=",cur_cmdNarrative,"  | M1 ",f_waveDirLabel(cur_dirM1)," M5 ",f_waveDirLabel(cur_dirM5)," H1 ",f_waveDirLabel(cur_dirH1)," H4 ",f_waveDirLabel(cur_dirH4));
      }
      ulong tk=trade.ResultOrder();
      // register live position (market entries fill immediately)
      if(posinfo.SelectByTicket(trade.ResultDeal())) {}
      // best-effort: register by scanning newest own position
      for(int q=PositionsTotal()-1;q>=0;q--){
         ulong pt=PositionGetTicket(q);
         if(pt==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)==(long)InpMagic && PositionGetString(POSITION_SYMBOL)==_Symbol){
            double psl=PositionGetDouble(POSITION_SL);
            double _openP=PositionGetDouble(POSITION_PRICE_OPEN);
            double _risk =MathAbs(_openP-slBase); if(_risk<=0) _risk=(cur_atr>0?cur_atr:10*_Point);
            //--- SPEC AUDIT: no TP1/partial registration. Position registered for SL tracking only. ---
            MgRegister(pt,psl,NA,dir);
            break;
         }
      }
   }
}

//==================================================================
// POSITION MANAGEMENT (every tick)
//==================================================================
//--- DEBUG: one line explaining WHY a trade was closed (so early exits can be mapped to the gate that fired) ---
void DbgExit(const string why,const ulong tk,const int dir,const double openP,const double mkt,const double rMult)
{
   if(!InpDebugExits) return;
   int cb=ConsensusBias();
   Print("=== EXIT  ",(dir==1?"BUY":"SELL")," #",tk,"  why=",why,
         "  R=",DoubleToString(rMult,2),
         "  open=",DoubleToString(openP,_Digits)," mkt=",DoubleToString(mkt,_Digits));
   Print("    CTX     : life=",DoubleToString(ctx_life,0),"  phase=",cur_ie1aPhase,"  narr=",ctx_narrState,
         "  chainVit=",DoubleToString(ctx_chainVitality,0),"  conv=",(ctx_converging?"Y":"n"),
         "  waveDir=",f_waveDirLabel(ctx_waveDir),"  thesis=",(cb==1?"BULL":cb==-1?"BEAR":"neutral"));
   Print("    OWNER   : ",cur_curveOwner," ",f_waveDirLabel(cur_ownerDir),"  trans=",cur_transState,
         "  | M1 ",f_waveDirLabel(cur_dirM1)," M5 ",f_waveDirLabel(cur_dirM5)," H1 ",f_waveDirLabel(cur_dirH1)," H4 ",f_waveDirLabel(cur_dirH4));
}
//--- DEBUG: one line explaining WHY a stop was moved (BE / trailing / migration) so 'stopped too early' can be traced ---
void DbgMod(const string why,const ulong tk,const int dir,const double oldSL,const double newSL,const double mkt)
{
   if(!InpDebugExits) return;
   Print("    SL-MOD  #",tk," ",why,"  ",(dir==1?"BUY":"SELL"),"  ",DoubleToString(oldSL,_Digits),
         " -> ",DoubleToString(newSL,_Digits),"  (mkt ",DoubleToString(mkt,_Digits),")");
}
//--- returns true (and arms the back-off flag) if the LAST trade request was rejected because the market is closed ---
bool MktClosed()
{
   uint rc=trade.ResultRetcode();
   if(rc==TRADE_RETCODE_MARKET_CLOSED || rc==TRADE_RETCODE_TRADE_DISABLED || rc==TRADE_RETCODE_CLOSE_ONLY){
      gMktClosed=true;
      if(InpDebugExits) Print("=== MARKET CLOSED -> backing off all order actions until next bar (rc=",rc,")");
      return true;
   }
   return false;
}
void ManagePositions()
{
   if(gMktClosed) return;
   //==================================================================
   // F72 RECURSIVE CURVE OWNERSHIP ENGINE -- CAMPAIGN MANAGEMENT
   //==================================================================
   // SPEC AUDIT: ALL artificial exits removed (TP/BE/trailing/session/thesis-flip/partial/
   // life-score/narrative/phase-flip/opposite-signal). Recursive waves naturally contain
   // pullbacks, internal liquidation, and ownership oscillation -- these are NORMAL.
   //
   // EXIT ONLY on:
   // 1) OWNERSHIP TRANSFER -- the opposing curve now dominates (new curve > InpOwnerTransferThresh %)
   // 2) TERMINAL SEQUENCE COMPLETION -- the campaign's S/D transition completed (ctx_termComplete
   //    AND the owner is no longer the trade direction AND transfer is confirmed)
   // 3) PHASE-2 CHOCH AGAINST POSITION -- internal structure proves campaign failure (an
   //    opposite-direction CHoCH on the owner rung while the campaign is in Transition)
   //
   // The position lives until one of these triggers OR the structure SL (hard stop on the broker
   // server, placed at the entry's actual invalidation). No price target, no time limit.
   //==================================================================
   double atr=cur_atr; if(atr<=0) atr=10*_Point;
   for(int q=PositionsTotal()-1;q>=0;q--){
      ulong tk=PositionGetTicket(q);
      if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      int    dir   =PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      double openP =PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL =PositionGetDouble(POSITION_SL);
      sym.RefreshRates();
      double mkt   =(dir==1?sym.Bid():sym.Ask());
      int    mi    =MgIndex(tk);
      double initSL=(mi>=0?gMgInitSL[mi]:curSL);
      double risk  =MathAbs(openP-initSL); if(risk<=0 || initSL<=0) risk=atr;
      double rMult =(dir==1?(mkt-openP):(openP-mkt))/risk;

      //==============================================================
      // 30-MIN TRADE QUALITY PROTECTION
      //==============================================================
      double posProfit=PositionGetDouble(POSITION_PROFIT);
      double posLots  =PositionGetDouble(POSITION_VOLUME);
      // heldBars computed here so QProt log can use it (also used by hold gate below)
      int heldBars=(int)((TimeCurrent()-(datetime)PositionGetInteger(POSITION_TIME))/MathMax(PeriodSeconds(_Period),1));
      if(InpQProtEnabled && mi>=0){
         // -- continuously update MFE / MAE (in R) --
         double excursion=(dir==1?(mkt-openP):(openP-mkt));
         double rNow=(risk>0)?excursion/risk:0.0;
         if(rNow>gMgMFE[mi]) gMgMFE[mi]=rNow;
         if((-rNow)>gMgMAE[mi]) gMgMAE[mi]=-rNow;

         // trade age in minutes
         int ageMin=(int)((TimeCurrent()-gMgEntryTime[mi])/60);

         // -- QUALITY LOG: emit once per bar when protection is relevant --
         bool logBar=(heldBars>=1 && ageMin>=(mi>=0&&gMgTradeType[mi]==0?InpCampaignProtMin:InpQProtMinutes) && !gMgP1Done[mi]);
         if(logBar){
            string qLog="QUALITY: AgeMin="+IntegerToString(ageMin)+
                         " L1Hit="+(gMgP1Done[mi]?"Y":"N")+
                         " MFE="+DoubleToString(gMgMFE[mi],2)+"R"+
                         " MAE="+DoubleToString(gMgMAE[mi],2)+"R"+
                         " ProtMode="+(gMgQProtMode[mi]?"Y":"N")+
                         " InProfit="+(posProfit>0?"Y":"N")+
                         " #"+IntegerToString((int)tk);
            if(InpDebugExits) Print(qLog);
         }

         // -- age >= 30 min (or 120 for Campaign trades), L1 not yet hit --
         // Campaign trades use InpCampaignProtMin (default 120): slow Asia builds need time
         // before management intervenes. Momentum uses InpQProtMinutes (default 30).
         int _qprotThresh=(mi>=0 && gMgTradeType[mi]==0) ? InpCampaignProtMin : InpQProtMinutes;
         if(ageMin>=_qprotThresh && !gMgP1Done[mi]){
            if(!gMgQProtMode[mi]){
               gMgQProtMode[mi]=true;
               if(InpDebugExits) Print("=== QPROT ON #",tk," age=",ageMin,"m  profit=",
                  DoubleToString(posProfit,0),"  MFE=",DoubleToString(gMgMFE[mi],2),
                  "R MAE=",DoubleToString(gMgMAE[mi],2),"R");
            }

            double newSL=0;
            if(posProfit>0){
               // ---- PATH A: IN PROFIT -- aggressive trail ----
               // Trail to just below the last 2 bars' swing low (long)
               // or just above the last 2 bars' swing high (short).
               // Adds 0.3 ATR buffer so normal noise doesn't stop it out.
               double swing=(dir==1)?DBL_MAX:-DBL_MAX;
               for(int bb=1;bb<=2;bb++){
                  if(dir==1){ double lo=iLow(_Symbol,_Period,bb);  if(lo>0 && lo<swing) swing=lo; }
                  else       { double hi=iHigh(_Symbol,_Period,bb); if(hi>0 && hi>swing) swing=hi; }
               }
               if(swing==DBL_MAX||swing==-DBL_MAX) swing=mkt; // fallback
               double trailBuf=atr*0.30;
               newSL=(dir==1)?NormPrice(swing-trailBuf):NormPrice(swing+trailBuf);
               // Only improve (never widen); must keep SL below/above market
               bool improve=(dir==1&&newSL>curSL)||(dir==-1&&newSL<curSL);
               if(improve){
                  double minD=MinStopDist()+_Point;
                  bool sideOK=(dir==1?newSL<mkt-minD:newSL>mkt+minD);
                  if(sideOK && trade.PositionModify(tk,newSL,0.0)){
                     curSL=newSL;
                     if(InpDebugExits) Print("=== QPROT TRAIL -> ",DoubleToString(newSL,_Digits),
                        "  (swing=",DoubleToString(swing,_Digits),
                        " profit=$",DoubleToString(posProfit,0),")  #",tk);
                  }
               }
            } else {
               // ---- PATH B: FLAT / LOSING -- protection floor ----
               // Tighten SL to entry - 0.25R using swing + fractional risk floor.
               double protDist=InpQProtSLFrac*risk;
               double protSL=(dir==1)?(openP-protDist):(openP+protDist);
               double swingLevel=(dir==1)?DBL_MAX:-DBL_MAX;
               for(int bb=1;bb<=3;bb++){
                  if(dir==1){ double lo=iLow(_Symbol,_Period,bb);  if(lo>0 && lo<swingLevel) swingLevel=lo; }
                  else       { double hi=iHigh(_Symbol,_Period,bb); if(hi>0 && hi>swingLevel) swingLevel=hi; }
               }
               if(swingLevel==DBL_MAX||swingLevel==-DBL_MAX) swingLevel=protSL;
               if(dir==1) newSL=NormPrice(MathMax(protSL,MathMin(swingLevel,openP)));
               else       newSL=NormPrice(MathMin(protSL,MathMax(swingLevel,openP)));
               bool improve=(dir==1&&newSL>curSL)||(dir==-1&&newSL<curSL);
               if(improve){
                  double minD=MinStopDist()+_Point;
                  bool sideOK=(dir==1?newSL<mkt-minD:newSL>mkt+minD);
                  if(sideOK && trade.PositionModify(tk,newSL,0.0)){
                     curSL=newSL;
                     if(InpDebugExits) Print("=== QPROT PROTECT -> ",DoubleToString(newSL,_Digits),
                        "  (prot=",DoubleToString(protSL,_Digits),
                        " swing=",DoubleToString(swingLevel,_Digits),")  #",tk);
                  }
               }
            }
         }

         // -- ESCALATION: age >= 45 min (or 180 for Campaign), L1 still not hit --
         int _escalThresh=(mi>=0 && gMgTradeType[mi]==0) ? (InpCampaignProtMin+60) : InpQEscalMinutes;
         if(ageMin>=_escalThresh && !gMgP1Done[mi] && !gMgQExit50[mi]){
            gMgQExit50[mi]=true;
            double escalLots=(InpQEscalHalf)?NormalizeLot(posLots*0.50):posLots;
            double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            if(escalLots<minLot) escalLots=minLot;
            if(escalLots>=posLots){
               DbgExit("QPROT-escalation-full (age="+IntegerToString(ageMin)+"m, L1 not hit, profit="+DoubleToString(posProfit,0)+")",
                       tk,dir,openP,mkt,rMult);
               if(!trade.PositionClose(tk) && MktClosed()) return;
               continue;
            } else {
               if(trade.PositionClosePartial(tk,escalLots) && InpDebugExits)
                  Print("=== QPROT PARTIAL 50% age=",ageMin,"m  R=",
                        DoubleToString(rMult,2)," profit=$",DoubleToString(posProfit,0),
                        " MFE=",DoubleToString(gMgMFE[mi],2),"R  #",tk);
            }
         }
      } // end quality protection block

      //==============================================================
      // PROFIT MANAGEMENT -- 5 levels, 20% each
      // $900 -> 20% + breakeven SL
      // $2300 -> 20%
      // $4400 -> 20%
      // $1600 -> 20%
      // $3300 -> 20%
      // $4500 -> 20%
      // $6000 -> 20%
      // $7000+ -> aggressive swing trail
      //==============================================================
      // posProfit and posLots already computed above in quality block
      if(mi>=0 && posLots>0 && posProfit>0){
         double closeLots=NormalizeLot(posLots*0.20);  // 20% of current position
         if(closeLots<=0) closeLots=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);

         // Level 1 -- $900 profit: close 20% + move SL to breakeven
         // BE SL uses ATR buffer (not 1 point): audit showed 88% of L1 trades wicked at 1-point BE.
         // Campaign trades get wider buffer (0.5 ATR) -- slow builds retrace deeper before continuing.
         // Momentum trades get 0.3 ATR -- tight enough to protect, wide enough to survive normal noise.
         if(!gMgP1Done[mi] && posProfit>=900.0){
            gMgP1Done[mi]=true;
            if(closeLots<posLots && trade.PositionClosePartial(tk,closeLots))
               if(InpDebugExits) Print("=== PARTIAL L1 @$900 closed ",DoubleToString(closeLots,2)," lots profit=",DoubleToString(posProfit,2));
            double _beAtr=(mi>=0 && gMgTradeType[mi]==0) ? atr*InpBEAtrCampaign : atr*InpBEAtrBuf;
            double beSL=(dir==1)? NormPrice(openP+_beAtr) : NormPrice(openP-_beAtr);
            if((dir==1&&beSL>curSL)||(dir==-1&&beSL<curSL)){
               double _minD=MinStopDist()+_Point;
               bool _sideOK=(dir==1?beSL<mkt-_minD:beSL>mkt+_minD);
               if(_sideOK && trade.PositionModify(tk,beSL,0.0)){
                  curSL=beSL;
                  if(InpDebugExits) Print("=== BREAKEVEN SL moved to ",DoubleToString(beSL,_Digits),
                     "  (type=",(gMgTradeType[mi]==0?"Campaign":"Momentum"),
                     " buf=",DoubleToString(_beAtr,_Digits),")");
               }
            }
         }
         // Level 2 -- $1600 profit: close 20%
         else if(gMgP1Done[mi] && !gMgP2Done[mi] && posProfit>=1600.0){
            gMgP2Done[mi]=true;
            if(closeLots<posLots && trade.PositionClosePartial(tk,closeLots))
               if(InpDebugExits) Print("=== PARTIAL L2 @$1600 closed ",DoubleToString(closeLots,2)," lots");
         }
         // Level 3 -- $3300 profit: close 20%
         else if(gMgP2Done[mi] && !gMgP3Done[mi] && posProfit>=3300.0){
            gMgP3Done[mi]=true;
            if(closeLots<posLots && trade.PositionClosePartial(tk,closeLots))
               if(InpDebugExits) Print("=== PARTIAL L3 @$3300 closed ",DoubleToString(closeLots,2)," lots");
         }
         // Level 4 -- $4500 profit: close 20%
         else if(gMgP3Done[mi] && !gMgP4Done[mi] && posProfit>=4500.0){
            gMgP4Done[mi]=true;
            if(closeLots<posLots && trade.PositionClosePartial(tk,closeLots))
               if(InpDebugExits) Print("=== PARTIAL L4 @$4500 closed ",DoubleToString(closeLots,2)," lots");
         }
         // Level 5 -- $6000 profit: close 20%
         else if(gMgP4Done[mi] && !gMgP5Done[mi] && posProfit>=6000.0){
            gMgP5Done[mi]=true;
            if(closeLots<posLots && trade.PositionClosePartial(tk,closeLots))
               if(InpDebugExits) Print("=== PARTIAL L5 @$6000 closed ",DoubleToString(closeLots,2)," lots");
         }

         // Aggressive trailing -- activates once profit crosses $7000
         // Uses swing structure (last 2 bars + 0.3 ATR buffer) -- tighter than ATR*2
         if(!gMgTrailing[mi] && posProfit>=7000.0){
            gMgTrailing[mi]=true;
            // Seed trail at last 2-bar swing
            double seedSwing=(dir==1)?DBL_MAX:-DBL_MAX;
            for(int bb=1;bb<=2;bb++){
               if(dir==1){ double lo=iLow(_Symbol,_Period,bb);  if(lo>0&&lo<seedSwing) seedSwing=lo; }
               else       { double hi=iHigh(_Symbol,_Period,bb); if(hi>0&&hi>seedSwing) seedSwing=hi; }
            }
            if(seedSwing==DBL_MAX||seedSwing==-DBL_MAX) seedSwing=(dir==1)?(mkt-atr*1.0):(mkt+atr*1.0);
            gMgTrailSL[mi]=(dir==1)?seedSwing-atr*0.30:seedSwing+atr*0.30;
            if(InpDebugExits) Print("=== AGGRESSIVE TRAIL ON @$7000  seedSL=",DoubleToString(gMgTrailSL[mi],_Digits));
         }
         if(gMgTrailing[mi]){
            // Update trail every bar: last 2-bar swing + 0.3 ATR buffer
            double swing=(dir==1)?DBL_MAX:-DBL_MAX;
            for(int bb=1;bb<=2;bb++){
               if(dir==1){ double lo=iLow(_Symbol,_Period,bb);  if(lo>0&&lo<swing) swing=lo; }
               else       { double hi=iHigh(_Symbol,_Period,bb); if(hi>0&&hi>swing) swing=hi; }
            }
            if(swing==DBL_MAX||swing==-DBL_MAX) swing=(dir==1)?(mkt-atr*1.0):(mkt+atr*1.0);
            double newTrail=(dir==1)?NormPrice(swing-atr*0.30):NormPrice(swing+atr*0.30);
            bool improved=(dir==1&&newTrail>gMgTrailSL[mi])||(dir==-1&&newTrail<gMgTrailSL[mi]);
            if(improved){
               double minD=MinStopDist()+_Point;
               bool sideOK=(dir==1?newTrail<mkt-minD:newTrail>mkt+minD);
               if(sideOK && trade.PositionModify(tk,newTrail,0.0)){
                  gMgTrailSL[mi]=newTrail;
                  if(InpDebugExits) Print("=== TRAIL SL -> ",DoubleToString(newTrail,_Digits),
                     "  (swing=",DoubleToString(swing,_Digits),")  profit=$",DoubleToString(posProfit,0));
               }
            }
         }
      }

      //--- minimum hold gate: never exit on the entry bar (noise) ---
      // heldBars already computed above (before QProt block)
      if(heldBars<InpMinHoldBars) continue;

      //--- EXIT 1: OWNERSHIP TRANSFER -- the curve that owns price has fully transferred
      //  to the opposing direction. This means the campaign we entered is no longer dominant;
      //  a new campaign in the opposite direction has taken over.
      //  CHURN FIX: death entries must hold for InpDeathMinHoldBars before this can fire --
      //  because the death signal fires WHILE the macro curve still shows high dominance.
      //  Exiting at bar 3 (InpMinHoldBars) guarantees R~0 exits. Give death entries more
      //  time to see the actual ownership shift they predicted.
      if(InpExitOnOwnerTransfer){
         int _holdRequired = (mi>=0 && gMgIsDeathEntry[mi]) ? InpDeathMinHoldBars : InpMinHoldBars;
         bool _heldEnough = (heldBars >= _holdRequired);
         bool ownerOpposed=(cur_ownerDir!=0 && cur_ownerDir!=dir);
         bool domHigh=(cur_domTransfer>=InpOwnerTransferThresh);
         if(ownerOpposed && domHigh && _heldEnough){
            DbgExit("ownership-transfer (owner "+cur_curveOwner+" "+f_waveDirLabel(cur_ownerDir)+" dom "+DoubleToString(cur_domTransfer,0)+"%)",tk,dir,openP,mkt,rMult);
            if(!trade.PositionClose(tk) && MktClosed()) return;
            continue;
         }
      }

      //--- EXIT 2: TERMINAL SEQUENCE COMPLETION -- the campaign naturally reached its
      //  supply/demand terminal and the transition is complete. The campaign is finished;
      //  the ownership engine says the curve has delivered its full objective. ---
      if(InpExitOnTermComplete){
         bool termDone=(InpUseV60Context && ctx_termComplete);
         //  Only fire this exit if the terminal sequence belongs to the OPPOSING campaign
         //  (i.e., the ENTRY campaign's curve has been consumed and a new terminal against
         //  it has matured). If the terminal is in OUR direction, it's our entry zone forming -- hold.
         bool termAgainstUs=(termDone && cur_ownerDir!=0 && cur_ownerDir!=dir);
         if(termAgainstUs){
            DbgExit("terminal-sequence-complete (campaign finished, owner "+cur_curveOwner+" "+f_waveDirLabel(cur_ownerDir)+")",tk,dir,openP,mkt,rMult);
            if(!trade.PositionClose(tk) && MktClosed()) return;
            continue;
         }
      }

      //--- EXIT 3: PHASE-2 CHOCH AGAINST POSITION -- internal structure has broken against
      //  the campaign. This is a confirmed failure: the campaign tried to expand but the
      //  opposing wave printed a CHoCH on the owner rung (or higher), proving the campaign
      //  cannot hold. Requires confirmation bars to filter noise. ---
      if(InpExitOnP2CHOCH){
         //  A Phase-2 CHOCH = the owner curve's transition state is "BUILDING" or "EXPANSION"
         //  (it tried to push in our direction) but the owner direction has FLIPPED against us.
         //  The cur_transState being early ("BUILDING"/"EXPANSION") while the owner opposes us
         //  means the structure just broke. Combined with sufficient bars, this is confirmed.
         bool ownerFlipped=(cur_ownerDir!=0 && cur_ownerDir!=dir);
         bool earlyTrans=(cur_transState=="BUILDING" || cur_transState=="EXPANSION");
         //  Additional confirmation: the wave direction on the owner timeframe must also oppose.
         bool waveConfirm=(ctx_waveDir!=0 && ctx_waveDir!=dir);
         if(ownerFlipped && earlyTrans && waveConfirm && heldBars>=InpMinHoldBars+InpP2CHOCHConfirmBars){
            DbgExit("P2-CHOCH-against (owner flipped to "+f_waveDirLabel(cur_ownerDir)+" trans="+cur_transState+", campaign failed)",tk,dir,openP,mkt,rMult);
            if(!trade.PositionClose(tk) && MktClosed()) return;
            continue;
         }
      }
   }
}

//==================================================================
// SYMPHONY COMPOSITE EXHAUSTION EXIT
//==================================================================
//--- Close ONLY when the move has objectively run its course - three independent confirmations
//  must agree: (1) price reached the convex ARC apex region, (2) the curve/phase collapsed
//  (the dominant wave flipped against the trade), (3) a sweep+reclaim rejection printed at the
//  extreme (liquidity grab). This is "exit at terminal exhaustion" - it lets winners run to the
//  curve apex instead of cutting early, but still banks before giving it all back. ---
void ManageExhaustionExit()
{
   if(!InpUseExhaustionExit) return;
   if(gMktClosed) return;
   if(CountOwnPositions()<=0) return;
   double a=cur_atr; if(a<=0) a=10*_Point;
   int nb=(int)ArraySize(eaC);
   if(nb<3) return;
   int idx=nb-2, prv=nb-3;                 // last CLOSED bar + the one before
   double hi=eaH[idx], lo=eaL[idx], cl=eaC[idx];
   double mid=(hi+lo)*0.5;
   sym.RefreshRates();
   for(int q=PositionsTotal()-1;q>=0;q--)
   {
      ulong tk=PositionGetTicket(q); if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      int dir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1);
      //--- GATE: this exit BANKS A WINNER at terminal exhaustion. It must NEVER fire on a fresh
      //  or losing trade. A terminal-reversal entry is, by design, counter to the still-printing
      //  wave at entry, so phaseCollapse (ctx_waveDir!=dir) is true the instant we open and the
      //  entry's own sweep+reclaim can satisfy the sweep test -> without these gates the trade
      //  was being closed on the entry bar (the "cut as soon as it opens" bug). ---
      int heldBars=(int)((TimeCurrent()-(datetime)PositionGetInteger(POSITION_TIME))/MathMax(PeriodSeconds(_Period),1));
      if(heldBars<MathMax(InpMinHoldBars,1)) continue;          // give the move room first
      double openP=PositionGetDouble(POSITION_PRICE_OPEN);
      double px   =(dir==1?sym.Bid():sym.Ask());
      bool   inProfit=(dir==1? px>openP : px<openP);
      if(!inProfit) continue;                                   // only bank a move that ran our way
      //--- 1) ARC exhaustion: price reached the convex apex region ---
      bool arcHit=false;
      if(!naf(ctx_arcApex) && ctx_arcDir==dir)
         arcHit=(dir==1)? (hi>=ctx_arcApex-InpArcTolATR*a) : (lo<=ctx_arcApex+InpArcTolATR*a);
      //--- 2) phase / curve collapse: the dominant wave has flipped against the trade ---
      bool phaseCollapse=(ctx_waveDir!=0 && ctx_waveDir!=dir);
      //--- 3) sweep + reclaim rejection at the extreme (institutional liquidity grab) ---
      bool sweepReclaim=(dir==1)? (hi>eaH[prv] && cl<mid) : (lo<eaL[prv] && cl>mid);
      if(arcHit && phaseCollapse && sweepReclaim)
      {
         if(InpDebugExits) Print("=== EXHAUSTION EXIT ",(dir==1?"BUY":"SELL")," #",tk,
                                  "  arc=",DoubleToString(ctx_arcApex,_Digits),
                                  "  waveDir=",ctx_waveDir,"  sweep+reclaim @",DoubleToString(cl,_Digits));
         if(!trade.PositionClose(tk) && MktClosed()) return;
      }
   }
}

//==================================================================
// STATUS PANEL
//==================================================================
void ShowStatus()
{
   if(!InpShowStatus) return;
   string s="";
   s+="LETRA 37 EA  ["+_Symbol+","+EnumToString(_Period)+"]\n";
   s+="Phase  : "+cur_currentDisplayPhase+"  (M5 "+f_waveDirLabel(cur_dirM5)+")\n";
   s+="DOE    : REMOVED -- ownership death engine is authority\n";
   s+="Grade  : REMOVED -- no grade/TQE/ERF gates\n";
   s+="Opp    : REMOVED -- no opportunity score gates\n";
   s+="Stop   : "+PXs(cur_invActiveStop)+(cur_invInvalidated?" [INVALID]":"")+"   Target "+PXs(!naf(ctx_netTarget)?ctx_netTarget:ctx_attractorPx)+"\n";
   s+="Dest   : "+cur_tplWinnerClass+" "+PXs(cur_tplMainTarget)+" ("+cur_tplSource+")\n";
   s+="Pos    : "+IntegerToString(CountOwnPositions())+"   TradesToday "+IntegerToString(gTradesToday)+"\n";
   s+="Gate   : "+gEntryBlock+"\n";
   // UNIFIED OWNERSHIP DEATH display -- shows all 4 signals so the panel matches Gate 7 exactly
   string _ds1Tx = (nz(MapVal(se240.t,se240.dom,se240.n,TimeCurrent()))>40.0||nz(MapVal(se60.t,se60.dom,se60.n,TimeCurrent()))>40.0) ? "SE?" : "SE?";
   string _ds4Tx = ctx_life < (double)InpCurveDeadBelow ? "Life?" : "Life?";
   string _deathTx = IntegerToString(cur_ownerDeathSignals)+"/4";
   string _gateTx  = cur_ownerDeathSignals>=2 ? "OPEN ("+_deathTx+")" : "BLOCKED ("+_deathTx+")";
   s+="Curve  : own "+cur_curveOwner+" "+f_waveDirLabel(cur_ownerDir)+"  "+cur_transState+"  ["+cur_entryReady+"]\n";
   s+="Death  : "+_gateTx+"  "+_ds1Tx+"  LTF-rev  HOE-wt  "+_ds4Tx+"  life="+R0(ctx_life)+"\n";
   s+="Recur  : dom "+R0(cur_domTransfer)+"%  comp "+cur_compRegime+"  depth "+IntegerToString(cur_recDepth)+"/"+IntegerToString(cur_expRecDepth)+(cur_mtfEntryFresh?("  | RET "+cur_mtfEntryTF+" "+(cur_mtfEntryDir==1?"L":"S")+" dom "+R0(cur_mtfEntryDom)+"%"):"")+"\n";
   s+="Cap    : budget "+R0(cur_curveBudget)+"%  toFlip "+DoubleToString(cur_distFlipAtr,1)+"ATR  entryP "+R0(cur_entryProb)+"%\n";
   s+="ARC    : apex "+PXs(ctx_arcApex)+"  now "+PXs(ctx_arcNow)+"  dir "+(ctx_arcDir==1?"up":ctx_arcDir==-1?"down":"-")+"\n";
   if(InpUseV60Context) s+="Camp   : "+ctx_campaign+"  toFlip "+DoubleToString(ctx_distFlipAtr,1)+"ATR"+(ctx_atFlip?("  shifts "+IntegerToString(ctx_termShifts)+"/"+IntegerToString(ctx_termExpected)+" m1 "+IntegerToString(ctx_termM1Cycles)+(ctx_termComplete?" DONE":"")):"")+(ctx_fuMerged?"  [FU merged->parent]":"")+"\n";
   if(InpUseV60Context) s+="Induc  : "+(ctx_failureSwing?"FAILURE SWING (spring) - ":"")+(ctx_atTrueInduction?"TRUE INDUCTION (lowest flip "+PXs(ctx_lowestFlip)+")":ctx_inManipBand?"MANIPULATION band 0.618-0.786 (wait)":"-")+"\n";
   s+="Narr   : "+cur_cmdNarrative;
   if(InpUseV60Context){
      s+="\n--- v60 context ---";
      s+="\nNet "+(ctx_netBias==1?"BULL":ctx_netBias==-1?"BEAR":"-")+"  Stack "+(ctx_stackDir==1?"BULL":ctx_stackDir==-1?"BEAR":"-")+" "+R0(ctx_stackPct)+"%  press "+R0(ctx_pressure);
      s+="\nCurve "+ctx_alive+"  life "+R0(ctx_life)+"  force "+ctx_cpState;
      s+="\nv60Phase "+ctx_phase+"  Narr "+ctx_narrState+" "+R0(ctx_narrative)+(ctx_converging?" (converging)":"");
      s+="\nTime "+(ctx_timeDir==1?"CLIMB":ctx_timeDir==-1?"DIVE":"LEVEL")+" "+R0(ctx_timeAlign)+"%  H1 "+ctx_h1Timing+"  attr "+PXs(ctx_attractorPx);
      s+="\nFU node "+(ctx_fuFresh?((ctx_fuDir==1?"BULL @ ":"BEAR @ ")+PXs(ctx_fuTip)):"- (none fresh)");
   }
   Comment(s);
}

//==================================================================
// OnTick
//==================================================================
void OnTick()
{
   MgCleanup();
   DailyRollover();

   // manage open trades every tick (uses last computed cur_* engine state)
   if(g_lastProcessed>=0) ManagePositions();

   datetime bt=iTime(_Symbol,_Period,0);
   bool newBar=(bt!=gLastBarTime);
   if(newBar){
      gLastBarTime=bt;
      gMktClosed=false;          // new bar -> market may have reopened; re-allow management/flip order actions
      ComputeEngine();          // full recompute -> sets cur_* for last closed bar
      if(g_lastProcessed>=0){
         ManageExhaustionExit(); // SYMPHONY composite terminal-exhaustion exit (closed-bar)
         TryEnter();             // evaluate entry on the just-closed bar
         if(InpDebugBlocks && StringFind(gEntryBlock,"ENTERED")<0 && gEntryBlock!="-" && gEntryBlock!="no signal (awaiting Return)")
            Print("[no-entry] ",gEntryBlock,"   | owner ",cur_curveOwner," ",cur_transState," camp ",ctx_campaign," dom ",DoubleToString(cur_domTransfer,0),"%");
         ManagePositions();      // re-manage with fresh engine state
         ShowStatus();
      }
   }
}
//+------------------------------------------------------------------+
// v_adbe3f9 - l4_dir/l2_dir fix applied
