{-# LANGUAGE DoAndIfThenElse #-}

module Handler.Update where

import Import
import qualified Eve.Api.Char.WalletTransactions as WT
import qualified Eve.Api.Types as T
import qualified Eve.Api.Char.Standings as ST
import qualified Eve.Api.Char.Skills as SK

accountingId :: Int64
accountingId = 16622
brokerRelationId :: Int64
brokerRelationId = 3446

getUpdateR :: Handler Html
getUpdateR = loginOrDo (\(uid,user) -> do
               man <- getHttpManager <$> ask
               apiKey <- runDB $ getBy $ UniqueApiUser uid
               now <- liftIO getCurrentTime
               case apiKey of
                 Nothing -> return ()
                 Just (Entity _ (Api _ k v)) -> do
                   let apidata = T.mkComplete k v (userCharId user)
                   --update skills
                   when (userSkillTimeout user < now) $
                     do
                     skills <- liftIO $ SK.getSkills man apidata
                     case skills of
                       T.QueryResult time' skills' -> runDB $ do
                                         update uid [UserAcc =. findLvl accountingId skills']
                                         update uid [UserBr =. findLvl brokerRelationId skills']
                                         update uid [UserSkillTimeout =. time']
                       _ -> return ()
                   --update standings
                   when (userStandingsTimeout user < now) $
                     do
                     standings <- liftIO $ ST.getStandings man apidata
                     case standings of
                       T.QueryResult time' (_,cstand,fstand) -> runDB $ do
                                         deleteWhere [CorpStandingsUser ==. uid]
                                         deleteWhere [FactionStandingsUser ==. uid]
                                         insertMany_ (migrateCorpStandings uid <$> cstand)
                                         insertMany_ (migrateFactionStandings uid <$> fstand)
                                         update uid [UserStandingsTimeout =. time']
                       _ -> return ()
                   --update transactions
                   when (userWalletTimeout user < now) $
                     do
                     lastid <- runDB $ selectFirst [TransactionUser ==. uid] [Desc TransactionTransId]
                     trans <- case lastid of
                       Just (Entity _ t) -> liftIO $ WT.getWalletTransactionsBackTo man apidata (transactionTransId t)
                       Nothing           -> liftIO $ WT.getWalletTransactionsBackTo man apidata 0
                     case trans of
                       T.QueryResult time' trans' -> runDB $ do
                                                           update uid [UserWalletTimeout =. time']
                                                           insertMany_ (migrateTransaction uid <$> trans')
                       _ -> return ()
                 --let sql = "update"
                 --runDB $ rawExecute sql [uid]
               redirect WalletR
             )

findLvl :: Int64 -> [SK.Skill] -> Int
findLvl sid skills = case find (\(SK.Skill sid' _ _ _) -> sid' == sid) skills of
                     Just (SK.Skill _ _ lvl _) -> lvl
                     Nothing -> 0

migrateCorpStandings :: UserId -> ST.Standing -> CorpStandings
migrateCorpStandings u (ST.Standing cid cname standing) = CorpStandings u cid cname standing

migrateFactionStandings :: UserId -> ST.Standing -> FactionStandings
migrateFactionStandings u (ST.Standing cid cname standing) = FactionStandings u cid cname standing

migrateTransaction :: UserId -> WT.Transaction -> Transaction
migrateTransaction u (WT.Transaction dt tid q tn ti pc ci cn si sn tt tf jti) =
    Transaction u dt tid q (if tis tt then -q else q) tn ti
                (fromIntegral pc) ci cn si sn (tis tt) (tfc tf) jti
                Nothing Nothing Nothing Nothing False
    where
      tis :: WT.TransactionType -> Bool
      tis WT.Sell = True
      tis WT.Buy = False
      tfc :: WT.TransactionFor -> Bool
      tfc WT.Corporation = True
      tfc WT.Personal = False
