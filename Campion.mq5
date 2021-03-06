//+------------------------------------------------------------------+
//|                                                      Campion.mq5 |
//|                        Copyright 2020, Fabiano Campion           |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "2020, Fabiano Campion"
#property description "Hey, welcome to the 100% winning expert." // Description (line 1)
#property description "The input parameters are optimized for EURUSD M15."         // Description (line 2)
#property version   "1.50"
#include<Trade\Trade.mqh>

//--- input parameters
//max_orders da moltiplicare x5 dato che max_orders è il numero di famiglie di ordini
input int      max_orders=20; 
input double   beginning_size=0.01;
input double   size_increase_factor=1.5;
//50 pips è meglio
input double      stop_profit_pips=60.0;
input int EXPERT_MAGIC=123456;

input double up_Bound = 1.35;
input double un_Bound = 0.95;
input double spread = 15.0;
input double sarDiff = 13;
input double sarDiffMembers = 13;
input double takeProfitLossPerc = 0.01;
input double minTakeProfitLossPips = 10;

//--- Declaration of constants
#define TEST_STORIA 1
#define FATT_PM 0.012      //Scostamento dall'ultimo BUY o SELL nuova famiglia 0.012 ideale
#define FATT_BS 0.006      //Scostamento dall'ultimo BUY o SELL in famiglia 0.006 ideale 
#define CONTRACT_SIZE 100000.0 //1 lotto di EURUSD equivale a 100000 euro
#define OP_BUY 0           //Buy 
#define OP_SELL 1          //Sell 
#define OP_BUYLIMIT 2      //Pending order of BUY LIMIT type 
#define OP_SELLLIMIT 3     //Pending order of SELL LIMIT type 
#define OP_BUYSTOP 4       //Pending order of BUY STOP type 
#define OP_SELLSTOP 5      //Pending order of SELL STOP type 
#define EXPERT_COMMENT "Campion 1.50 EXPERT"
#define TOT_VERSIONS 4 // numero totale di versioni
//--- Global variables
struct Famiglia_ordini {
   MqlTradeRequest trade_request[5];
   MqlTradeResult trade_result[5];
   double takeProfit[5];
   double maxValProfitBuy;
   double maxValProfitSell;
   int membro_attuale; //posizione all'interno della famiglia del prossimo ordine da creare
};
Famiglia_ordini dettagli_posizioni[]; //sono memorizzate tutte le posizioni che sto seguendo
int contatore_famiglie=0; //quando una famiglia sarà al completo aumento di 1 e faccio divisione con resto
                          //per 20 così vado in cerchio e verifico ogni volta che gli ordini siano chiusi
                          //prima di rischiare di sovrascriverli e fare troppi ordini
//per aspettare di vedere il risultato di un ordine
datetime LastTradeTime = 0;
int cont=0;
input int FrequencyUpdate = 1;
bool ROpen=true;
datetime UpdateTime = 0;
CTrade trade;
ulong last_order_ticket=-1; //ultimo ticket dell'ultimo deal fatto da robot 
ulong last_closed_order=-1;
//int last_order_closed_op=-1; //assegno OP_BUY o OP_SELL
//double last_order_closed_time=0.0;
//In EURUSD 0.01 lotti corrispondono a 1000€ euro
int trade_counter=0; //non so perchè ma ad ogni operazione di trade la funzione OnTrade() viene chiamata 5 volte
double equity_iniziale=0;
double MinLot=0.0;
double MaxLot=0.0;
int LotDigits=2;
string last_version[TOT_VERSIONS]={"Campion 1.31 EXPERT","Campion 1.40 EXPERT","Campion 1.42 EXPERT","Campion 1.50 EXPERT"};

//nel primo ordine di una famiglia ho moltiplicato i pips*3 così riduco le probabilità di riaprire subito un altro ordine nella stessa direzione

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   ChartSetSymbolPeriod(0,"EURUSD",PERIOD_M15);
   printf("ACCOUNT_LOGIN =  %d",AccountInfoInteger(ACCOUNT_LOGIN));
   printf("ACCOUNT_LEVERAGE =  %d",AccountInfoInteger(ACCOUNT_LEVERAGE));
   equity_iniziale=AccountInfoDouble(ACCOUNT_EQUITY);
   bool thisAccountTradeAllowed=AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
   bool EATradeAllowed=AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
   ENUM_ACCOUNT_TRADE_MODE tradeMode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   ENUM_ACCOUNT_STOPOUT_MODE stopOutMode=(ENUM_ACCOUNT_STOPOUT_MODE)AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE);
   //--- Inform about the possibility to perform a trade operation
   if(thisAccountTradeAllowed)
      Print("Trade for this account is permitted");
   else
      Print("Trade for this account is prohibited!");
 
//--- Find out if it is possible to trade on this account by Expert Advisors
   if(EATradeAllowed)
      Print("Trade by Expert Advisors is permitted for this account");
   else
      Print("Trade by Expert Advisors is prohibited for this account!");
 
//--- Find out the account type
   switch(tradeMode)
     {
      case(ACCOUNT_TRADE_MODE_DEMO):
         Print("This is a demo account");
         break;
      case(ACCOUNT_TRADE_MODE_CONTEST):
         Print("This is a competition account");
         break;
      default:Print("This is a real account!");
     }
 
//inizializzo il vettore delle famiglie di posizioni al numero massimo di ordini
     ArrayResize(dettagli_posizioni,sizeof(Famiglia_ordini)* max_orders);     
     for(int i=max_orders-1;i>=0;i--){
         dettagli_posizioni[i].membro_attuale=0;
         dettagli_posizioni[i].maxValProfitBuy=0;
         dettagli_posizioni[i].maxValProfitSell=3;
         for(int j=4;j>=0;j--){
            dettagli_posizioni[i].trade_request[j].type=-1;
            dettagli_posizioni[i].trade_request[j].price=0;
            dettagli_posizioni[i].trade_result[j].price=0;
            dettagli_posizioni[i].trade_request[j].action==-1;
            dettagli_posizioni[i].takeProfit[j]=-1;
            
         }
     }
//Vedo se ho ordini aperti di versioni precedenti del programma o di questo e li inserisco nel database
create_db();

   MinLot = SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
   MaxLot = SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
   if(MinLot == 0.001) LotDigits = 3;
   if(MinLot == 0.01)  LotDigits = 2;
   if(MinLot == 0.1)   LotDigits = 1;
   
//aggiorno la storia da selezionare
   HistorySelect(0,TimeCurrent());
//--- create timer
   EventSetTimer(1);
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- destroy timer
   EventKillTimer();
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   HistorySelect(0,TimeCurrent());
   int posizioni=PositionsTotal();
   double Ask=NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK),_Digits);
   double Bid=NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID),_Digits);
   double equity=0;
   int ordini_non_canc=CountOrdersNotCanceled();
   int ordini_canc=CountOrdersCanceled();
   double new_price_tag=0.0; //nuovo prezzo per il take profit calcolato
   UpdateTime = StringToTime( TimeToString( TimeCurrent() + FrequencyUpdate, TIME_SECONDS ));
   equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity>equity_iniziale+equity_iniziale*10/100){
      SendNotification("Hai raggiunto un profitto del 10%");
      equity_iniziale=equity;
   }
   
   //funzione per cambiare i take profit raggiunti e fare pi schei
   
   for(int i=0;i<max_orders;i++)
   {
      int membroAttuale =  0;
      if(dettagli_posizioni[i].membro_attuale>0)
          membroAttuale = dettagli_posizioni[i].membro_attuale-1;
          
      if(dettagli_posizioni[i].trade_request[membroAttuale].type == OP_BUY)//se è BUY
      {
      //Print(dettagli_posizioni[i].takeProfit[membroAttuale]+" e "+Bid);
         if(dettagli_posizioni[i].takeProfit[membroAttuale] < Bid)//se in direzione favorevole...
         { 
         //Print(dettagli_posizioni[i].takeProfit[membroAttuale]);
            if(Bid > dettagli_posizioni[i].maxValProfitBuy)//...e se supero il valore del takeProfit Massimo precedente..
            {  
             //Print("fanculo1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
               if(Bid > dettagli_posizioni[i].maxValProfitBuy + dettagli_posizioni[i].maxValProfitBuy * takeProfitLossPerc)//..per non modificare troppe volte la posizione
               {
                  for(int j=membroAttuale ; j>=0 ;j--)
                  {
                     if(dettagli_posizioni[i].maxValProfitBuy+0.01*dettagli_posizioni[i].maxValProfitBuy < dettagli_posizioni[i].trade_request[j].tp && dettagli_posizioni[i].maxValProfitBuy+0.02*dettagli_posizioni[i].maxValProfitBuy > dettagli_posizioni[i].trade_request[j].tp)
                     {
                        trade.PositionModify(dettagli_posizioni[i].trade_result[j].order,NormalizeDouble(0.0,_Digits),NormalizeDouble(dettagli_posizioni[j].maxValProfitBuy+0.01*dettagli_posizioni[j].maxValProfitBuy,_Digits));
                     }
                  }
               }
               
               dettagli_posizioni[i].maxValProfitBuy = Bid;//...aggiorno valore             
            }
            else//... e se non lo supero, controllo di non essere sceso troppo
            { 
               if(dettagli_posizioni[i].maxValProfitBuy > 0 && Bid < dettagli_posizioni[i].maxValProfitBuy - dettagli_posizioni[i].maxValProfitBuy * takeProfitLossPerc / (membroAttuale + 1) && Bid > dettagli_posizioni[i].takeProfit[membroAttuale])//...se sono sceso troppo chiudo la posizione
               {
                  trade.PositionClose(dettagli_posizioni[i].trade_result[membroAttuale].order,100.0);
               }
            }
         }
         else{//... ma la direzione cambia subito dopo, allora aspetto "minTakeProfitLossPips" e poi chiudo tutto    
            if(dettagli_posizioni[i].maxValProfitBuy != 0 && Bid < dettagli_posizioni[i].takeProfit[membroAttuale] - minTakeProfitLossPips *_Point )
            {
               trade.PositionClose(dettagli_posizioni[i].trade_result[membroAttuale].order,100.0);
            }
         }
      }
      else if(dettagli_posizioni[i].trade_request[membroAttuale].type == OP_SELL)//se è SELL
      {
      //Print(dettagli_posizioni[i].takeProfit[membroAttuale]);
         if(dettagli_posizioni[i].takeProfit[membroAttuale] > Ask)
         { 
         //Print(dettagli_posizioni[i].maxValProfitSell);
            if(Ask < dettagli_posizioni[i].maxValProfitSell)
            {
               if(Ask < dettagli_posizioni[i].maxValProfitSell - dettagli_posizioni[i].maxValProfitSell * takeProfitLossPerc)
               {
                  trade.PositionModify(dettagli_posizioni[contatore_famiglie].trade_result[membroAttuale].order,NormalizeDouble(3.0,_Digits),NormalizeDouble(dettagli_posizioni[i].maxValProfitSell+0.01*dettagli_posizioni[i].maxValProfitSell,_Digits));
               
               
                  for(int j=membroAttuale ; j>=0 ;j--)
                  {
                     if(dettagli_posizioni[j].maxValProfitSell-0.01*dettagli_posizioni[j].maxValProfitSell > dettagli_posizioni[i].trade_request[j].tp && dettagli_posizioni[j].maxValProfitSell-0.02*dettagli_posizioni[j].maxValProfitSell < dettagli_posizioni[i].trade_request[j].tp)
                     {
                         trade.PositionModify(dettagli_posizioni[i].trade_result[j].order,NormalizeDouble(3.0,_Digits),NormalizeDouble(dettagli_posizioni[j].maxValProfitSell-0.01*dettagli_posizioni[j].maxValProfitSell,_Digits));
                     }
                  }
                  
               
               }                        
               dettagli_posizioni[i].maxValProfitSell = Ask;
            } 
            else
            { 
               if(dettagli_posizioni[i].maxValProfitSell < 3 && Ask > dettagli_posizioni[i].maxValProfitSell + dettagli_posizioni[i].maxValProfitSell * takeProfitLossPerc / (membroAttuale + 1) && Ask < dettagli_posizioni[i].takeProfit[membroAttuale])
               {
                   trade.PositionClose(dettagli_posizioni[i].trade_result[membroAttuale].order,100.0);
               }
            }
         }
         else{         
            if(dettagli_posizioni[i].maxValProfitSell != 3 && Ask > dettagli_posizioni[i].takeProfit[membroAttuale] + minTakeProfitLossPips *_Point )
            {
               trade.PositionClose(dettagli_posizioni[i].trade_result[membroAttuale].order,100.0);
            }
         }      
      }
   }
   
   
   // fine funzione pi schei
   
   if(PositionsTotal()==max_orders*5){}
   else{
     int membro=dettagli_posizioni[contatore_famiglie].membro_attuale;
    if(Ask>un_Bound && Ask<up_Bound && (Ask - Bid <= spread * _Point)){
    //ora provo a comprare o vendere
    if(TimeLocal() - LastTradeTime < 3){
      if(cont==0){
            Print("Two orders in less than 3 seconds, ORDER REQUEST DENIED");
            cont++;
      }
  }
  else{
   cont=0;
   if(membro>0){ //membro==0 vuol dire che si può aprire una nuova transazione
         //apro una nuova posizione nel prossimo membro della famiglia se BUY
         
         //creo i segnali in caso di membro > 0
         
         bool action = true;
         int sarArrayLength = 4;
         MqlRates PriceArray[];
         ArraySetAsSeries(PriceArray,true); //sort the array from the current candle downwards
         int Data=CopyRates(Symbol(),Period(),0,sarArrayLength,PriceArray); //dall'ora 0, cioè in quel momento, per sarArrayLength candles
         double mySARArray[];
         int SARDefinition=iSAR(_Symbol,Period(),0.02,0.2);
         ArraySetAsSeries(mySARArray,true);
         CopyBuffer(SARDefinition,0,0,sarArrayLength,mySARArray);
         //buy/sell signal
         //If last SAR value below candle  1 low
         
         for(int i=0;i <sarArrayLength -1 ;i++)
         {
            double SARValue=NormalizeDouble(mySARArray[i],_Digits);
            double SARValue1=NormalizeDouble(mySARArray[i+1],_Digits);
          
            if(MathAbs(SARValue - SARValue1) <= _Point*sarDiffMembers)
            {
               action = false;
               i = sarArrayLength;
            }
         }
         

         
         if(action && dettagli_posizioni[contatore_famiglie].trade_request[membro-1].type==ORDER_TYPE_BUY && dettagli_posizioni[contatore_famiglie].trade_result[membro-1].price > (Ask+dettagli_posizioni[contatore_famiglie].trade_result[membro-1].price*FATT_BS*(double)membro) ){ //((double)membro-0.2*(double)membro)
         if(dettagli_posizioni[contatore_famiglie].trade_request[membro].price==0){
            ZeroMemory(dettagli_posizioni[contatore_famiglie].trade_request[membro]);
            ZeroMemory(dettagli_posizioni[contatore_famiglie].trade_result[membro]);
            //devo elaborare il stop profit degli ordini
            new_price_tag=NormalizeDouble(calcola_profitBuy(Bid,Ask),_Digits);
            //Print("Price tag= "+new_price_tag);
           if(CheckVolumeValue(GetLotSize(dettagli_posizioni[contatore_famiglie].trade_request[membro-1].volume*size_increase_factor))&&CheckStopLoss_Takeprofit(ORDER_TYPE_BUY,0.0,new_price_tag,Ask,Bid)&&CheckMoneyForTrade(Symbol(),GetLotSize(dettagli_posizioni[contatore_famiglie].trade_request[membro-1].volume*size_increase_factor),ORDER_TYPE_BUY)){
            inserisci_req(TRADE_ACTION_DEAL, EXPERT_MAGIC,_Symbol,GetLotSize(dettagli_posizioni[contatore_famiglie].trade_request[membro-1].volume*size_increase_factor),Ask,0.0,NormalizeDouble(new_price_tag+0.01*new_price_tag,_Digits),ORDER_TYPE_BUY,ORDER_FILLING_FOK);
            dettagli_posizioni[contatore_famiglie].takeProfit[membro]=new_price_tag;
            LastTradeTime = TimeLocal();
            OrderSend(dettagli_posizioni[contatore_famiglie].trade_request[membro],dettagli_posizioni[contatore_famiglie].trade_result[membro]);
            //devo verificare che effettivamente ci sia una posizione in più
            if(!TEST_STORIA)while ( UpdateTime>= StringToTime( TimeToString( TimeCurrent(), TIME_SECONDS ) ) ){ //salto FrequencyUpdate tempo
            }
            else{Sleep(800);} //milliseconds
            last_order_ticket=dettagli_posizioni[contatore_famiglie].trade_result[membro].order;
            if(CountOrdersCanceled()>ordini_canc){//FALLIMENTO
               Print("BUY order failed");
               dettagli_posizioni[contatore_famiglie].trade_request[membro].price=0;//reimposto il prezzo per il prossimo ciclo
            }
            if(CountOrdersNotCanceled()>ordini_non_canc){ //SUCCESSO!
               Print("New BUY order at price "+ dettagli_posizioni[contatore_famiglie].trade_result[membro].price +" with volume "+ dettagli_posizioni[contatore_famiglie].trade_result[membro].volume +"and TICKET "+dettagli_posizioni[contatore_famiglie].trade_result[membro].order);
               //ora devo cambiare tutti i take profit degli ordini di quella famiglia
               //changeTakeProfit(new_price_tag);
               if(membro<4){
                  membro++;
                  dettagli_posizioni[contatore_famiglie].membro_attuale=membro;
               }
               else{
               //membro=0; //ho riempito i membri, incremento la famiglia
               //dettagli_posizioni[contatore_famiglie].membro_attuale=membro;
               contatore_famiglie=(contatore_famiglie+1)%max_orders;
               }
             }
            }
           }else { //in caso non sia stato registrato il membro precedente per qualche errore strano
               Print("New BUY order at price "+ dettagli_posizioni[contatore_famiglie].trade_result[membro].price +" with volume "+ dettagli_posizioni[contatore_famiglie].trade_result[membro].volume +"and TICKET "+dettagli_posizioni[contatore_famiglie].trade_result[membro].order);
               //ora devo cambiare tutti i take profit degli ordini di quella famiglia
               //changeTakeProfit(new_price_tag);
               if(membro<4){
                  membro++;
                  dettagli_posizioni[contatore_famiglie].membro_attuale=membro;
               }
               else{
               //membro=0; //ho riempito i membri, incremento la famiglia
               //dettagli_posizioni[contatore_famiglie].membro_attuale=membro;
               contatore_famiglie=(contatore_famiglie+1)%max_orders;
               }
           }
         }
         //apro una nuova posizione nel prossimo membro della famiglia se SELL
         if(action && dettagli_posizioni[contatore_famiglie].trade_request[membro-1].type==ORDER_TYPE_SELL && dettagli_posizioni[contatore_famiglie].trade_result[membro-1].price < Bid-(dettagli_posizioni[contatore_famiglie].trade_result[membro-1].price*FATT_BS*(double)membro) ){ //((double)membro-0.2*(double)membro)
         if(dettagli_posizioni[contatore_famiglie].trade_request[membro].price==0){
            ZeroMemory(dettagli_posizioni[contatore_famiglie].trade_request[membro]);
            ZeroMemory(dettagli_posizioni[contatore_famiglie].trade_result[membro]);
            //devo elaborare il stop profit degli ordini
            new_price_tag=NormalizeDouble(calcola_profitSell(Bid,Ask),_Digits);
           if(CheckVolumeValue(GetLotSize(dettagli_posizioni[contatore_famiglie].trade_request[membro-1].volume*size_increase_factor))&&CheckStopLoss_Takeprofit(ORDER_TYPE_SELL,3.0,new_price_tag,Ask,Bid)&&CheckMoneyForTrade(Symbol(),GetLotSize(dettagli_posizioni[contatore_famiglie].trade_request[membro-1].volume*size_increase_factor),ORDER_TYPE_SELL)){
            inserisci_req(TRADE_ACTION_DEAL, EXPERT_MAGIC,_Symbol,GetLotSize(dettagli_posizioni[contatore_famiglie].trade_request[membro-1].volume*size_increase_factor),Bid,3.0,NormalizeDouble(new_price_tag-0.01*new_price_tag,_Digits),ORDER_TYPE_SELL,ORDER_FILLING_FOK);
            dettagli_posizioni[contatore_famiglie].takeProfit[membro]=new_price_tag;
            LastTradeTime = TimeLocal();
            OrderSend(dettagli_posizioni[contatore_famiglie].trade_request[membro],dettagli_posizioni[contatore_famiglie].trade_result[membro]);
            //devo verificare che effettivamente ci sia una posizione in più
            if(!TEST_STORIA)while ( UpdateTime>= StringToTime( TimeToString( TimeCurrent(), TIME_SECONDS ) ) ){ //salto FrequencyUpdate tempo
            }
            else{Sleep(800);}
            last_order_ticket=dettagli_posizioni[contatore_famiglie].trade_result[membro].order;
            if(CountOrdersCanceled()>ordini_canc){//FALLIMENTO
               Print("SELL order failed");
               dettagli_posizioni[contatore_famiglie].trade_request[membro].price=0;//reimposto il prezzo per il prossimo ciclo
               }
            if(CountOrdersNotCanceled()>ordini_non_canc){ //SUCCESSO!
               Print("New SELL order at price  "+ dettagli_posizioni[contatore_famiglie].trade_result[membro].price +" with volume "+ dettagli_posizioni[contatore_famiglie].trade_result[membro].volume +"and TICKET "+dettagli_posizioni[contatore_famiglie].trade_result[membro].order);
               //ora devo cambiare tutti i take profit degli ordini di quella famiglia
               //changeTakeProfit(new_price_tag);
               if(membro<4){
                  membro++;
                  dettagli_posizioni[contatore_famiglie].membro_attuale=membro;
               }
               else{
               //membro=0; //ho riempito i membri, incremento la famiglia
               //dettagli_posizioni[contatore_famiglie].membro_attuale=membro;
               contatore_famiglie=(contatore_famiglie+1)%max_orders;
               }
             }
            } //checkvolume
           }else { //in caso non sia stato registrato il membro precedente per qualche errore strano
               Print("New SELL order at price "+ dettagli_posizioni[contatore_famiglie].trade_result[membro].price +" with volume "+ dettagli_posizioni[contatore_famiglie].trade_result[membro].volume +"and TICKET "+dettagli_posizioni[contatore_famiglie].trade_result[membro].order);
               //ora devo cambiare tutti i take profit degli ordini di quella famiglia
               //changeTakeProfit(new_price_tag);
               if(membro<4){
                  membro++;
                  dettagli_posizioni[contatore_famiglie].membro_attuale=membro;
               }
               else{
               //membro=0; //ho riempito i membri, incremento la famiglia
               //dettagli_posizioni[contatore_famiglie].membro_attuale=membro;
               contatore_famiglie=(contatore_famiglie+1)%max_orders;
               }
           }
         }
      }
      else{ 
         //creo i segnali in caso di membro == 0
         string signal="";
         int sarArrayLength =5;
         MqlRates PriceArray[];
         ArraySetAsSeries(PriceArray,true); //sort the array from the current candle downwards
         int Data=CopyRates(Symbol(),Period(),0,sarArrayLength,PriceArray); //dall'ora 0, cioè in quel momento, per sarArrayLength candles
         double mySARArray[];
         int SARDefinition=iSAR(_Symbol,Period(),0.02,0.2);//Period()
         ArraySetAsSeries(mySARArray,true);
         CopyBuffer(SARDefinition,0,0,sarArrayLength,mySARArray);
         double SARValue=NormalizeDouble(mySARArray[0],_Digits);
         double SARValue1=NormalizeDouble(mySARArray[1],_Digits);
         //buy/sell signal
         //If last SAR value below candle  1 low
         
         bool flagSarJump = false;
         string andamento= "";
         string andamento1= "";
         
         if(SARValue < PriceArray[0].low)
           andamento="up";
         else
           andamento="down";
         
         for(int i=1;i<sarArrayLength;i++)
         {
            double SARValueTemp=NormalizeDouble(mySARArray[i],_Digits);
            if(SARValueTemp < PriceArray[i].low)
              andamento1="up";
            else
              andamento1="down";
            if(andamento!=andamento1){ //se c'è stato un salto del sar negli ultimi 7 bici da sotto a sopra o contrario allora jump=true
               flagSarJump=true;
               i=sarArrayLength;
               }
         }
         
         
         if(!flagSarJump){
            if(SARValue < PriceArray[0].low && SARValue1 < PriceArray[1].low && ((SARValue - SARValue1) <= _Point*sarDiff)) 
             signal="sell";
            
           if(SARValue > PriceArray[0].high && SARValue1 > PriceArray[1].high && ((SARValue1 - SARValue) <= _Point*sarDiff)) 
             signal="buy"; 
         }  
             
         
         //apro una posizione BUY in caso di membro == 0
         // roba che ho tolto dall'if sotto
         //(dettagli_posizioni[(contatore_famiglie+max_orders-1)%max_orders].trade_request[4].type==ORDER_TYPE_BUY && dettagli_posizioni[(contatore_famiglie+max_orders-1)%max_orders].trade_result[4].price>(Ask+Ask*FATT_PM))||
         //ora se la famiglia precedente era un BUY allora faccio solo ordini sell
         if(signal=="buy" )if(dettagli_posizioni[(contatore_famiglie+max_orders-1)%max_orders].trade_request[4].price==0 || dettagli_posizioni[(contatore_famiglie+max_orders-1)%max_orders].trade_request[4].type==ORDER_TYPE_SELL || dettagli_posizioni[(contatore_famiglie+max_orders-1)%max_orders].trade_request[4].action==-1){//si passa alla prossima famiglia solo quando sono stati riempiti tutti i membri
         if(dettagli_posizioni[contatore_famiglie].trade_request[membro].price==0){
            ZeroMemory(dettagli_posizioni[contatore_famiglie].trade_request[membro]);
            ZeroMemory(dettagli_posizioni[contatore_famiglie].trade_result[membro]);
           if(CheckVolumeValue(GetLotSize(beginning_size))&&CheckStopLoss_Takeprofit(ORDER_TYPE_BUY,NormalizeDouble(0.0,_Digits),Ask+_Point*(stop_profit_pips),Ask,Bid)&&CheckMoneyForTrade(Symbol(),GetLotSize(beginning_size),ORDER_TYPE_BUY)){
            inserisci_req(TRADE_ACTION_DEAL, EXPERT_MAGIC,_Symbol,GetLotSize(beginning_size),Ask,NormalizeDouble(0.0,_Digits),NormalizeDouble((Ask+_Point*(stop_profit_pips))+0.01*(Ask+_Point*(stop_profit_pips)),_Digits),ORDER_TYPE_BUY,ORDER_FILLING_FOK);
            dettagli_posizioni[contatore_famiglie].takeProfit[membro]=Ask+_Point*(stop_profit_pips);
            LastTradeTime = TimeLocal();
            if(!OrderSend(dettagli_posizioni[contatore_famiglie].trade_request[membro],dettagli_posizioni[contatore_famiglie].trade_result[membro])){
               resettaFamiglia(contatore_famiglie);
               Print("BUY order failed");
            }
            //devo verificare che effettivamente ci sia una posizione in più
            if(!TEST_STORIA)while ( UpdateTime>= StringToTime( TimeToString( TimeCurrent(), TIME_SECONDS ) ) ){ //salto FrequencyUpdate tempo
            }
            else{Sleep(800);}
            last_order_ticket=dettagli_posizioni[contatore_famiglie].trade_result[membro].order;
            if(CountOrdersCanceled()>ordini_canc){//FALLIMENTO
               Print("BUY order failed");
               dettagli_posizioni[contatore_famiglie].trade_request[membro].price=0;//reimposto il prezzo per il prossimo ciclo
               }
            if(CountOrdersNotCanceled()>ordini_non_canc){ //SUCCESSO!
               Print("New BUY order at price "+ dettagli_posizioni[contatore_famiglie].trade_result[membro].price +" with volume "+ dettagli_posizioni[contatore_famiglie].trade_result[membro].volume +"and TICKET "+dettagli_posizioni[contatore_famiglie].trade_result[membro].order);
               membro++;
               dettagli_posizioni[contatore_famiglie].membro_attuale=membro;
             }
            }
           }else{
               Print("New BUY order at price "+ dettagli_posizioni[contatore_famiglie].trade_result[membro].price +" with volume "+ dettagli_posizioni[contatore_famiglie].trade_result[membro].volume +"and TICKET "+dettagli_posizioni[contatore_famiglie].trade_result[membro].order);
               membro++;
               dettagli_posizioni[contatore_famiglie].membro_attuale=membro;
           }
         }//se è SELL in caso di membro == 0
                              // roba che ho tolto dall'if sotto
                              //(dettagli_posizioni[(contatore_famiglie+max_orders-1)%max_orders].trade_request[4].type==ORDER_TYPE_SELL && dettagli_posizioni[(contatore_famiglie+max_orders-1)%max_orders].trade_result[4].price<(Bid+Bid*FATT_PM))||
          if(signal=="sell")if(dettagli_posizioni[(contatore_famiglie+max_orders-1)%max_orders].trade_request[4].price==0 || dettagli_posizioni[(contatore_famiglie+max_orders-1)%max_orders].trade_request[4].type==ORDER_TYPE_BUY || dettagli_posizioni[(contatore_famiglie+max_orders-1)%max_orders].trade_request[4].action==-1){//si passa alla prossima famiglia solo quando sono stati riempiti tutti i membri
          if(dettagli_posizioni[contatore_famiglie].trade_request[membro].price==0){
            ZeroMemory(dettagli_posizioni[contatore_famiglie].trade_request[membro]);
            ZeroMemory(dettagli_posizioni[contatore_famiglie].trade_result[membro]);
           if(CheckVolumeValue(GetLotSize(beginning_size))&&CheckStopLoss_Takeprofit(ORDER_TYPE_SELL,NormalizeDouble(3.0,_Digits),Bid-_Point*(stop_profit_pips),Ask,Bid)&&CheckMoneyForTrade(Symbol(),GetLotSize(beginning_size),ORDER_TYPE_SELL)){
            inserisci_req(TRADE_ACTION_DEAL, EXPERT_MAGIC,_Symbol,GetLotSize(beginning_size),Bid,NormalizeDouble(3.0,_Digits),NormalizeDouble((Bid-_Point*(stop_profit_pips))-0.01*(Bid-_Point*(stop_profit_pips)),_Digits),ORDER_TYPE_SELL,ORDER_FILLING_FOK);
            dettagli_posizioni[contatore_famiglie].takeProfit[membro]=Bid-_Point*(stop_profit_pips);
            LastTradeTime = TimeLocal();
            if(!OrderSend(dettagli_posizioni[contatore_famiglie].trade_request[membro],dettagli_posizioni[contatore_famiglie].trade_result[membro])){
               resettaFamiglia(contatore_famiglie);
               Print("SELL order failed");
            }
            //devo verificare che effettivamente ci sia una posizione in più
            if(!TEST_STORIA)while ( UpdateTime>= StringToTime( TimeToString( TimeCurrent(), TIME_SECONDS ) ) ){ //salto FrequencyUpdate tempo
            }
            else{Sleep(800);}
            last_order_ticket=dettagli_posizioni[contatore_famiglie].trade_result[membro].order;
            if(CountOrdersCanceled()>ordini_canc){//FALLIMENTO
               Print("SELL order failed");
               dettagli_posizioni[contatore_famiglie].trade_request[membro].price=0;//reimposto il prezzo per il prossimo ciclo
               }
            if(CountOrdersNotCanceled()>ordini_non_canc){ //SUCCESSO!
               Print("New SELL order at price "+ dettagli_posizioni[contatore_famiglie].trade_result[membro].price +" with volume "+ dettagli_posizioni[contatore_famiglie].trade_result[membro].volume +"and TICKET "+dettagli_posizioni[contatore_famiglie].trade_result[membro].order);
               membro++;
               dettagli_posizioni[contatore_famiglie].membro_attuale=membro;
             }
            }
           }
           else{
               Print("New SELL order at price "+ dettagli_posizioni[contatore_famiglie].trade_result[membro].price +" with volume "+ dettagli_posizioni[contatore_famiglie].trade_result[membro].volume +"and TICKET "+dettagli_posizioni[contatore_famiglie].trade_result[membro].order);
               membro++;
               dettagli_posizioni[contatore_famiglie].membro_attuale=membro;
           }
          }    
      }
        
    }//else della verifica del tempo tra 2 tentativi di transazione
   }//if prezzo tra 0.95&&1.30
  }//if iniziale che vede se ho raggiunto il massimo di max_orders famiglie e 5 membri per ogni famiglia = 100 posizioni aperte totali
  }
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
//---
   Print("Total Orders: "+CountOrdersNotCanceled());
   Print("Open Positions: "+PositionsTotal());
   Print("BUY Positions: "+CountPositions(POSITION_TYPE_BUY));
   Print("Sell Positions: "+CountPositions(POSITION_TYPE_SELL));
   Print("Member:"+dettagli_posizioni[contatore_famiglie].membro_attuale+" max=5");
   Print("Family :"+contatore_famiglie+" max="+max_orders);
   Print("--------------------");
   EventKillTimer();
   EventSetTimer(1800);
  }
//+------------------------------------------------------------------+
//| Trade function                                                   |
//+------------------------------------------------------------------+
void OnTrade()
  {
//---
         verifica_ordini();
      
  }
//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
//---
   
  }
//+------------------------------------------------------------------+


//funzione per contare le posizioni aperte del tipoPosizione (POSITION_TYPE_BUY o ORDER_TYPE_SELL)
int CountPositions(ENUM_POSITION_TYPE tipoOrdine){
   int numberOfPositions=0;
   for(int i=PositionsTotal()-1; i>=0; i--){
      PositionGetTicket(i);
      string currencyPair=PositionGetString(POSITION_SYMBOL);
      if(_Symbol==currencyPair) //_Symbol sul grafico attuale
         if(PositionGetInteger(POSITION_TYPE)==tipoOrdine)
            numberOfPositions++;
    }
   return numberOfPositions;
}

//funzione per contare gli ordini totali che siano stati eseguiti (non conta quelli cancellati)
int CountOrdersNotCanceled(){
   int numberOfSuccessfulOrders=HistoryOrdersTotal();
   HistorySelect(0,TimeCurrent());
   ulong t=0;
   for(int i=HistoryOrdersTotal()-1;i>=0;i--){
      t=HistoryOrderGetTicket(i);
      if(HistoryOrderGetInteger(t, ORDER_STATE)!=ORDER_STATE_FILLED)
         numberOfSuccessfulOrders--;
   }
   return numberOfSuccessfulOrders;
}

int CountOrdersCanceled(){
   int numberOfUnSuccessfulOrders=HistoryOrdersTotal();
   HistorySelect(0,TimeCurrent());
   ulong t=0;
   for(int i=HistoryOrdersTotal()-1;i>=0;i--){
      t=HistoryOrderGetTicket(i);
      if(HistoryOrderGetInteger(t, ORDER_STATE)!=ORDER_STATE_REJECTED)
         numberOfUnSuccessfulOrders--;
   }
   return numberOfUnSuccessfulOrders;
}

//calcolatore di PIPS
double pips_unit_factor(){
   if(_Digits >= 4)
	   return 0.0001;
   else
   	return 0.01;
}

void inserisci_req(
   ENUM_TRADE_REQUEST_ACTIONS    action,          // Tipo d'operazione di trade 
   ulong                         magic,            // Expert Advisor ID (magic number) 
   string                        symbol,           // Simbolo di trade 
   double                        volume,           // Volume richiesto per un affare, in lotti 
   double                        price,            // Prezzo  
   double                        sl,               // Livello Stop Loss dell'ordine 
   double                        tp,               // Take Profit level dell'ordine  
   ENUM_ORDER_TYPE               type,             // Tipo di ordine 
   ENUM_ORDER_TYPE_FILLING       type_filling     // Tipo d'esecuzione dell'ordine 
   )
   {
   int membro=dettagli_posizioni[contatore_famiglie].membro_attuale;
   dettagli_posizioni[contatore_famiglie].trade_request[membro].action=action;
   dettagli_posizioni[contatore_famiglie].trade_request[membro].magic=magic;
   dettagli_posizioni[contatore_famiglie].trade_request[membro].symbol=symbol;
   dettagli_posizioni[contatore_famiglie].trade_request[membro].volume=volume;
   dettagli_posizioni[contatore_famiglie].trade_request[membro].price=price;
   dettagli_posizioni[contatore_famiglie].trade_request[membro].sl=sl;
   dettagli_posizioni[contatore_famiglie].trade_request[membro].tp=tp;
   dettagli_posizioni[contatore_famiglie].trade_request[membro].deviation=10.0*_Point;
   dettagli_posizioni[contatore_famiglie].trade_request[membro].type=type;
   dettagli_posizioni[contatore_famiglie].trade_request[membro].type_filling=type_filling;
   dettagli_posizioni[contatore_famiglie].trade_request[membro].comment=EXPERT_COMMENT;
}

void azzera_price(int i){
   for(int j=4;j>=0;j--){
            dettagli_posizioni[i].trade_request[j].price=0;
         }
}

double calcola_profitBuy(double bid, double ask){
   int membro=dettagli_posizioni[contatore_famiglie].membro_attuale;
   double profit=0;
   double price_des=0;
   double volume_tot=0;
   for(int i=membro-1;i>=0;i--){
      profit=profit+(bid-dettagli_posizioni[contatore_famiglie].trade_result[i].price) * dettagli_posizioni[contatore_famiglie].trade_result[i].volume * CONTRACT_SIZE;
      volume_tot=volume_tot+dettagli_posizioni[contatore_famiglie].trade_result[i].volume;
   }
   //in profit va calcolata anche la perdita relativa allo spread
   profit = profit+(bid-ask)*(dettagli_posizioni[contatore_famiglie].trade_result[membro-1].volume*size_increase_factor) * CONTRACT_SIZE;
   volume_tot=volume_tot+(dettagli_posizioni[contatore_famiglie].trade_result[membro-1].volume*size_increase_factor);
   //profit sarà negativo sicuramente e voglio recuperare tutto con la prossima transazione
   profit=-profit;
   price_des=ask+profit/(volume_tot*CONTRACT_SIZE)+stop_profit_pips*_Point*(double)membro;
   return NormalizeDouble(price_des,_Digits);
}

double calcola_profitSell(double bid, double ask){
   int membro=dettagli_posizioni[contatore_famiglie].membro_attuale;
   double profit=0;
   double price_des=0;
   double volume_tot=0;
   for(int i=membro-1;i>=0;i--){
      profit=profit+(dettagli_posizioni[contatore_famiglie].trade_result[i].price-ask) * dettagli_posizioni[contatore_famiglie].trade_result[i].volume * CONTRACT_SIZE;
      volume_tot=volume_tot+dettagli_posizioni[contatore_famiglie].trade_result[i].volume;
   }
   //in profit va calcolata anche la perdita relativa allo spread
   profit = profit+(bid-ask)*(dettagli_posizioni[contatore_famiglie].trade_result[membro-1].volume*size_increase_factor) * CONTRACT_SIZE;
   volume_tot=volume_tot+(dettagli_posizioni[contatore_famiglie].trade_result[membro-1].volume*size_increase_factor);
   //profit sarà negativo sicuramente e voglio recuperare tutto con la prossima transazione
   profit=-profit;
   price_des=bid-profit/(volume_tot*CONTRACT_SIZE)-stop_profit_pips*_Point*(double)membro; //stop profit aumenta un po' per guadagnare di più in base al numero di ordini aperti
   return NormalizeDouble(price_des,_Digits);
}

void changeTakeProfit(double price){ //non posso usarla perchè MT non accetta TP sotto all'opening price
   int membro=dettagli_posizioni[contatore_famiglie].membro_attuale;
   if(price>0)for(int i=membro-1;i>=0;i--){
      if(price!=dettagli_posizioni[contatore_famiglie].trade_request[i].tp)trade.PositionModify(dettagli_posizioni[contatore_famiglie].trade_result[i].order,NormalizeDouble(0.0,_Digits),price);
   }
}

void resettaFamiglia(int n){
    dettagli_posizioni[n].membro_attuale=0;
    dettagli_posizioni[n].maxValProfitBuy=0;
    dettagli_posizioni[n].maxValProfitSell=3;
 
    for(int j=4;j>=0;j--){
       dettagli_posizioni[n].trade_request[j].type=-1;
       dettagli_posizioni[n].trade_request[j].price=0.0;
       dettagli_posizioni[n].trade_result[j].price=0.0;
       dettagli_posizioni[n].takeProfit[j]=-1;
       
    }
}

//+------------------------------------------------------------------+ 
//| Returns the last order ticket in history or -1                    | 
//+------------------------------------------------------------------+ 
ulong GetLastOrderTicket() 
  { 
//--- request history for the last 7 days 
   if(!HistorySelect(0,TimeCurrent())) 
     { 
      //--- notify on unsuccessful call and return -1 
      Print(__FUNCTION__," HistorySelect() returned false"); 
      return -1; 
     } 
//---  
   ulong first_order,last_order,deals=HistoryOrdersTotal(); 
//--- work with orders if there are any 
   if(deals>0) 
     {  
      first_order=HistoryOrderGetTicket(0);  
      if(deals>1) 
        { 
         last_order=HistoryOrderGetTicket((int)deals-1);  
         return last_order; 
        } 
      return first_order; 
     } 
//--- no deal found, return -1 
   return -1; 
  } 
//+--------------------------------------------------------------------------+ 
//| Requests history for the last days and returns false in case of failure  | //Non usata
//+--------------------------------------------------------------------------+ 
bool GetTradeHistory(int days) 
  { 
//--- set a week period to request trade history 
   datetime to=TimeCurrent(); 
   datetime from=to-days*PeriodSeconds(PERIOD_D1); 
   ResetLastError(); 
//--- make a request and check the result 
   if(!HistorySelect(from,to)) 
     {  
      return false; 
     } 
//--- history received successfully 
   return true; 
  }
  
void verifica_ordini(){
  ulong pos_ticket=0;
  bool pos_exist=false;
  HistorySelect(0,TimeCurrent());
      //vedo se è stato chiuso qualche ordine perchè ha raggiunto il take profit e azzero la famiglia
      ulong last_order=GetLastOrderTicket(); //order e deal sono diversi ma ok poi li cambierò. Devo lavorare con gli order
      HistoryOrderSelect(last_order);
      if(HistoryOrderGetString(last_order,ORDER_SYMBOL)==Symbol())LastTradeTime = TimeLocal();
//      Print("Ordine fatto da robot "+last_order_ticket );
//      Print("Ordine chiuso manualmente "+HistoryOrderGetInteger(last_order,ORDER_POSITION_ID) );
/*      if(last_order_ticket!=HistoryOrderGetInteger(last_order,ORDER_POSITION_ID)&&last_order_ticket!=-1){
         for(int i=0;i<max_orders;i++){
            for(int j=0;j<5;j++){
               if(dettagli_posizioni[i].trade_result[j].order==HistoryOrderGetInteger(last_order,ORDER_POSITION_ID)){
                  Print("Ho chiuso l'ordine "+HistoryOrderGetInteger(last_order,ORDER_POSITION_ID) );
                  resettaFamiglia(i);
                  j=5;
                  i=max_orders;
                }
            }
         }
      }
*/
      //ora in caso sia lo stesso verifico che non sia una posizione aperta e se esiste allora non faccio niente
      if(last_order_ticket==HistoryOrderGetInteger(last_order,ORDER_POSITION_ID)&&last_order_ticket!=-1){
         for(int i=PositionsTotal()-1;i>=0;i--){
             pos_ticket = PositionGetTicket(i);
             if(PositionGetInteger(POSITION_TICKET)==last_order_ticket){
               pos_exist=true;
             }
         }
      }
         //se non esiste, significa che è stata chiusa e quindi devo resettare la famiglia
         if(pos_exist==false){
            for(int i=0;i<max_orders;i++){
               for(int j=0;j<5;j++){
                  HistoryOrderSelect(last_order);
                  //Print ("Prova prova"+dettagli_posizioni[i].trade_result[j].order+ "Prova prova"+ HistoryOrderGetInteger(last_order,ORDER_POSITION_ID));
                  if(dettagli_posizioni[i].trade_result[j].order==HistoryOrderGetInteger(last_order,ORDER_POSITION_ID)){
                     if(last_closed_order!=HistoryOrderGetInteger(last_order,ORDER_POSITION_ID)){
                        Print("Order closed "+HistoryOrderGetInteger(last_order,ORDER_POSITION_ID) );
                        }
                     last_closed_order=HistoryOrderGetInteger(last_order,ORDER_POSITION_ID);
                     chiudiFamiglia(i,last_closed_order);
                     resettaFamiglia(i);
                     j=5;
                     i=max_orders;
                }
            }
         }
         }
      
}

void chiudiFamiglia(int n, ulong closed_order){ //chiude tutti gli ordini aperti di quella famiglia
    int membri = dettagli_posizioni[n].membro_attuale;
    if(membri==5)membri--;
    for(int j=membri;j>=0;j--){
       if(dettagli_posizioni[n].trade_result[j].order!=closed_order){
         trade.PositionClose(dettagli_posizioni[n].trade_result[j].order,100.0);
       }
    }
}

bool CheckVolumeValue(double volume)
  {
//--- minimal allowed volume for trade operations
   double min_volume=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
   string description;
   if(volume<min_volume)
     {
      description=StringFormat("Volume is less than the minimal allowed SYMBOL_VOLUME_MIN=%.2f",min_volume);
      return(false);
     }

//--- maximal allowed volume of trade operations
   double max_volume=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
   if(volume>max_volume)
     {
      description=StringFormat("Volume is greater than the maximal allowed SYMBOL_VOLUME_MAX=%.2f",max_volume);
      return(false);
     }

//--- get minimal step of volume changing
   double volume_step=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_STEP);

   int ratio=(int)MathRound(volume/volume_step);
   if(MathAbs(ratio*volume_step-volume)>0.0000001)
     {
      description=StringFormat("Volume is not a multiple of the minimal step SYMBOL_VOLUME_STEP=%.2f, the closest correct volume is %.2f",
                               volume_step,ratio*volume_step);
      return(false);
     }
   description="Correct volume value";
   return(true);
  }
  
  double GetLotSize(double Lot){    
   if (Lot>=MaxLot) Lot = MaxLot;
   if (Lot<MinLot) Lot = MinLot;
   Lot = NormalizeDouble(Lot,LotDigits);
   return(Lot);
}

bool CheckStopLoss_Takeprofit(ENUM_ORDER_TYPE type,double SL,double TP, double Ask, double Bid)
  {
//--- get the SYMBOL_TRADE_STOPS_LEVEL level
   int stops_level=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   //if(stops_level!=0)
   //  {
   //   PrintFormat("SYMBOL_TRADE_STOPS_LEVEL=%d: StopLoss and TakeProfit must"+
   //               " not be nearer than %d points from the closing price",stops_level,stops_level);
   //  }
//---
   bool SL_check=false,TP_check=false;
//--- check only two order types
   switch(type)
     {
      //--- Buy operation
      case  ORDER_TYPE_BUY:
        {
         //--- check the StopLoss
         SL_check=(Bid-SL>stops_level*_Point);
         if(!SL_check)
            PrintFormat("For order %s StopLoss=%.5f must be less than %.5f"+
                        " (Bid=%.5f - SYMBOL_TRADE_STOPS_LEVEL=%d points)",
                        EnumToString(type),SL,Bid-stops_level*_Point,Bid,stops_level);
         //--- check the TakeProfit
         TP_check=(TP-Bid>stops_level*_Point);
         if(!TP_check)
            PrintFormat("For order %s TakeProfit=%.5f must be greater than %.5f"+
                        " (Bid=%.5f + SYMBOL_TRADE_STOPS_LEVEL=%d points)",
                        EnumToString(type),TP,Bid+stops_level*_Point,Bid,stops_level);
         //--- return the result of checking
         return(SL_check&&TP_check);
        }
      //--- Sell operation
      case  ORDER_TYPE_SELL:
        {
         //--- check the StopLoss
         SL_check=(SL-Ask>stops_level*_Point);
         if(!SL_check)
            PrintFormat("For order %s StopLoss=%.5f must be greater than %.5f "+
                        " (Ask=%.5f + SYMBOL_TRADE_STOPS_LEVEL=%d points)",
                        EnumToString(type),SL,Ask+stops_level*_Point,Ask,stops_level);
         //--- check the TakeProfit
         TP_check=(Ask-TP>stops_level*_Point);
         if(!TP_check)
            PrintFormat("For order %s TakeProfit=%.5f must be less than %.5f "+
                        " (Ask=%.5f - SYMBOL_TRADE_STOPS_LEVEL=%d points)",
                        EnumToString(type),TP,Ask-stops_level*_Point,Ask,stops_level);
         //--- return the result of checking
         return(TP_check&&SL_check);
        }
      break;
     }
//--- a slightly different function is required for pending orders
   return false;
  }
  
  bool CheckMoneyForTrade(string symb,double lots,ENUM_ORDER_TYPE type)
  {
//--- Getting the opening price
   MqlTick mqltick;
   SymbolInfoTick(symb,mqltick);
   double price=mqltick.ask;
   if(type==ORDER_TYPE_SELL)
      price=mqltick.bid;
//--- values of the required and free margin
   double margin,free_margin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   //--- call of the checking function
   if(!OrderCalcMargin(type,symb,lots,price,margin))
     {
      //--- something went wrong, report and return false
      Print("Error in ",__FUNCTION__," code=",GetLastError());
      return(false);
     }
   //--- if there are insufficient funds to perform the operation
   if(margin>free_margin)
     {
      //--- report the error and return false
      Print("Not enough money for ",EnumToString(type)," ",lots," ",symb," Error code=",GetLastError());
      return(false);
     }
//--- checking successful
   return(true);
  }
  
void create_db(){ //funzione per ricreare il database in caso di crash o simili
  bool flag=false;
  bool flag_volume=false;
  double volume=beginning_size;
  int membro=0;
  int count=0;
  int membro_attuale_analizz=0; //analizzo i membri dalla posizione 0 alla 4 in ordine per non fare casini con le famiglie
   for(int i=0; i<PositionsTotal(); i++){ //scorro tutte le posizioni
      flag=false;
      membro=0;
      PositionGetTicket(i); //seleziona da solo dal più vecchio al più nuovo
      string currencyPair=PositionGetString(POSITION_SYMBOL);
      if(_Symbol==currencyPair){ //_Symbol sul grafico attuale
          for(int j=TOT_VERSIONS-1;j>=0;j--){
               if(StringCompare(PositionGetString(POSITION_COMMENT),last_version[j],false)==0){
                     flag=true; //ho trovato un ordine di una versione precedente
                     j=0;
               }
          }
          if(flag){ // se ho trovato nel commento una versione precedente allora lo inserisco nel database
               //vedo se la size è un multiplo di quella attuale
               for(int k=0;k<5;k++){
                  if(volume==PositionGetDouble(POSITION_VOLUME)){
                     flag_volume=true;
                     k=5;
                  }
                  else{
                     volume=volume*size_increase_factor;
                     membro++;
                  }
               }//for k
               if(flag_volume && membro==membro_attuale_analizz){//se ho trovato un volume papabile allora provo ad inserirlo
                  if(ricerca_ord_in_famiglia(PositionGetInteger(POSITION_TICKET),membro)){ //se esiste già da qualche parte allora non faccio niente
                     //nulla
                  }
                  else{//in caso non esista nulla inserisco l'ordine in una famiglia
                     if(membro==0 && contatore_famiglie<max_orders){ //caso membro zero famiglia
                        //alla fine contatore_famiglie sarà posizionato sulla famiglia più nuova
                        if(count!=0)contatore_famiglie++;
                        dettagli_posizioni[contatore_famiglie].trade_request[0].type=PositionGetInteger(POSITION_TYPE);
                        dettagli_posizioni[contatore_famiglie].trade_result[0].order=PositionGetInteger(POSITION_TICKET);
                        dettagli_posizioni[contatore_famiglie].trade_request[0].price=PositionGetDouble(POSITION_PRICE_OPEN);
                        dettagli_posizioni[contatore_famiglie].trade_result[0].price=PositionGetDouble(POSITION_PRICE_OPEN);
                        dettagli_posizioni[contatore_famiglie].trade_request[0].volume=PositionGetDouble(POSITION_VOLUME);
                        dettagli_posizioni[contatore_famiglie].trade_result[0].volume=PositionGetDouble(POSITION_VOLUME);
                        if(dettagli_posizioni[contatore_famiglie].trade_request[0].type==OP_BUY)
                           dettagli_posizioni[contatore_famiglie].takeProfit[dettagli_posizioni[contatore_famiglie].membro_attuale]=PositionGetDouble(POSITION_TP)*100/101;
                        else
                           dettagli_posizioni[contatore_famiglie].takeProfit[dettagli_posizioni[contatore_famiglie].membro_attuale]=PositionGetDouble(POSITION_TP)*100/99;
                        dettagli_posizioni[contatore_famiglie].membro_attuale++;
                        count++;
                        Print("Order correspondence found for ticket = "+PositionGetInteger(POSITION_TICKET));
                     }
                     else{//caso multiplo
                        for(int l=contatore_famiglie;l>=0;l--){
                           bool inserito=false;
                           int member_temp=dettagli_posizioni[contatore_famiglie].membro_attuale;
                           if(member_temp==membro && PositionGetInteger(POSITION_TYPE)==dettagli_posizioni[l].trade_request[0].action){ //se è OP_BUY o OP_SELL anche lui
                              if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY && calcola_prezzo_membro(member_temp, l, PositionGetInteger(POSITION_TYPE))>PositionGetDouble(POSITION_PRICE_OPEN) && calcola_prezzo_membro(member_temp, l, PositionGetInteger(POSITION_TYPE))-100*_Point<PositionGetDouble(POSITION_PRICE_OPEN)){
                                 dettagli_posizioni[l].trade_request[membro].type=PositionGetInteger(POSITION_TYPE);
                                 dettagli_posizioni[i].trade_result[membro].order=PositionGetInteger(POSITION_TICKET);
                                 dettagli_posizioni[l].trade_request[membro].price=PositionGetDouble(POSITION_PRICE_OPEN);
                                 dettagli_posizioni[l].trade_result[membro].price=PositionGetDouble(POSITION_PRICE_OPEN);
                                 dettagli_posizioni[l].trade_request[membro].volume=PositionGetDouble(POSITION_VOLUME);
                                 dettagli_posizioni[l].trade_result[membro].volume=PositionGetDouble(POSITION_VOLUME);
                                 if(dettagli_posizioni[l].trade_request[membro].type==OP_BUY)
                                   dettagli_posizioni[l].takeProfit[dettagli_posizioni[l].membro_attuale]=PositionGetDouble(POSITION_TP)*100/101;
                                 else
                                   dettagli_posizioni[l].takeProfit[dettagli_posizioni[l].membro_attuale]=PositionGetDouble(POSITION_TP)*100/99;
                                 dettagli_posizioni[l].membro_attuale++;
                                 inserito=true;
                              }
                              if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL && calcola_prezzo_membro(member_temp, l, PositionGetInteger(POSITION_TYPE))<PositionGetDouble(POSITION_PRICE_OPEN) && calcola_prezzo_membro(member_temp, l, PositionGetInteger(POSITION_TYPE))+100*_Point>PositionGetDouble(POSITION_PRICE_OPEN)){
                                 dettagli_posizioni[l].trade_request[membro].type=PositionGetInteger(POSITION_TYPE);
                                 dettagli_posizioni[i].trade_result[membro].order=PositionGetInteger(POSITION_TICKET);
                                 dettagli_posizioni[l].trade_request[membro].price=PositionGetDouble(POSITION_PRICE_OPEN);
                                 dettagli_posizioni[l].trade_result[membro].price=PositionGetDouble(POSITION_PRICE_OPEN);
                                 dettagli_posizioni[l].trade_request[membro].volume=PositionGetDouble(POSITION_VOLUME);
                                 dettagli_posizioni[l].trade_result[membro].volume=PositionGetDouble(POSITION_VOLUME);
                                 if(dettagli_posizioni[l].trade_request[membro].type==OP_BUY)
                                   dettagli_posizioni[l].takeProfit[dettagli_posizioni[l].membro_attuale]=PositionGetDouble(POSITION_TP)*100/101;
                                 else
                                   dettagli_posizioni[l].takeProfit[dettagli_posizioni[l].membro_attuale]=PositionGetDouble(POSITION_TP)*100/99;
                                 dettagli_posizioni[l].membro_attuale++;
                                 inserito=true;
                              }
                           }
                           if(inserito){
                              count++;
                              l=-1;
                              Print("Order correspondence found for ticket = "+PositionGetInteger(POSITION_TICKET));
                           }
                        }
                     }
                  }
               }
          }
       }      
       if(i==PositionsTotal()-1)membro_attuale_analizz++;
       if(membro_attuale_analizz<5 && i==PositionsTotal()-1)i=0;
    }//primo for 
    Print("--------------------");
    Print("... expert state resumed after update or power failure or other problem... ");
    Print("Inserted "+count+" orders in my database");
    Print("--------------------");
  }
  
bool ricerca_ord_in_famiglia(ulong ticket, int membro){
   for(int i=contatore_famiglie;i>=0;i--){
      if(dettagli_posizioni[i].trade_result[membro].order==ticket){
         return true;
      }
   }
   return false;
}

double calcola_prezzo_membro(int membro, int contatore_fam, long ot){
   double prezzo=dettagli_posizioni[contatore_fam].trade_result[membro-1].price;
   if(ot==POSITION_TYPE_BUY) prezzo=prezzo-prezzo*FATT_BS*(double)membro;
   if(ot==POSITION_TYPE_SELL) prezzo=prezzo+prezzo*FATT_BS*(double)membro;
   return prezzo;
}