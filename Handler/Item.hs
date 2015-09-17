module Handler.Item where

import Import

itemsPerPage :: Int
itemsPerPage = 100

getItemR :: Int64 -> Handler Html
getItemR transactionTypeId = getItemPagedR transactionTypeId 0

getItemPagedR :: Int64 -> Int -> Handler Html
getItemPagedR tid page =
   loginOrDo (\(uid,user) -> do
     items <- runDB $ selectList [TransactionTypeId ==. tid] [Desc TransactionDateTime, LimitTo itemsPerPage, OffsetBy (itemsPerPage*page)]
     total <- runDB $ count [TransactionTypeId ==. tid]
     let offset = itemsPerPage * page
     loginLayout user $ [whamlet|
              <div .panel .panel-default>
               $if page > 0
                 <div .panel-heading>#{itemsPerPage} Transactions (starting at #{offset})
               $else
                 <div .panel-heading>#{itemsPerPage} Transactions
               <table .table .table-condensed .small>
                 <tr>
                   <th .text-center>Time
                   <th .text-center>P/C
                   <th .text-center>B/S
                   <th .text-center>Item
                   <th .text-center>##
                   <th .text-center>ISK/Item
                   <th .text-center>ISK total
                   <th .text-center>ISK profit
                   <th .text-center>%
                   <th .text-center>Time
                   <th .text-center>Client
                   <th .text-center>Station
                   <th .text-center>?
                   <th .text-center>
                 $forall Entity _ t <- items
                   <tr>
                     <td>#{showDateTime $ transactionDateTime $ t}
                     $if transactionTransForCorp t
                       <td .corpTransaction .text-center>C
                     $else
                       <td .personalTransaction .text-center>P
                     $if transactionTransIsSell t
                       <td .sellTransaction .text-center>S
                     $else
                       <td .buyTransaction .text-center>B
                     <td>#{transactionTypeName t}
                     <td .numeric>#{transactionQuantity t}
                     <td .numeric>#{prettyISK $ transactionPriceCents t}
                     <td .numeric>#{prettyISK $ transactionQuantity t * transactionPriceCents t}
                     $maybe profit <- transRealProfit t
                       $if (&&) (transactionTransIsSell t) (profit > 0)
                         <td .numeric .profit>
                           #{prettyISK $ profit}
                       $elseif (&&) (transactionTransIsSell t) (profit < 0)
                         <td .numeric .loss>
                           #{prettyISK $ profit}
                       $elseif not (transactionTransIsSell t)
                         <td .numeric .buyfee>
                           #{prettyISK $ profit}
                       $else
                         <td .numeric>
                           #{prettyISK $ profit}
                       <td .numeric>
                         #{profitPercent profit t}%
                     $nothing
                       <td>
                         -
                       <td>
                     <td .duration>
                       $maybe secs <- transactionSecondsToSell t
                         #{showSecsToSell secs}
                       $nothing
                         &nbsp;
                     <td>#{transactionClientName t}
                     <td>#{transactionStationName t}
                     <td>
                     <td>
     |]
   )

