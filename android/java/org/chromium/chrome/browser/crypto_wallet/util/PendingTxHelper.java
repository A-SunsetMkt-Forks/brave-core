/* Copyright (c) 2021 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.crypto_wallet.util;

import androidx.lifecycle.LiveData;
import androidx.lifecycle.MutableLiveData;

import org.chromium.brave_wallet.mojom.AccountInfo;
import org.chromium.brave_wallet.mojom.TransactionInfo;
import org.chromium.brave_wallet.mojom.TransactionStatus;
import org.chromium.brave_wallet.mojom.TxService;
import org.chromium.chrome.browser.crypto_wallet.observers.TxServiceObserverImpl;
import org.chromium.chrome.browser.crypto_wallet.observers.TxServiceObserverImpl.TxServiceObserverImplDelegate;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class PendingTxHelper implements TxServiceObserverImplDelegate {
    private TxService mTxService;
    private AccountInfo[] mAccountInfos;
    private final HashMap<String, TransactionInfo[]> mTxInfos;
    private final boolean mReturnAll;
    private final List<TransactionInfo> mTransactionInfos;
    private final List<TransactionCacheRecord> mCacheTransactionInfos;
    private boolean isFetchingTx;
    private final MutableLiveData<TransactionInfo> _mSelectedPendingRequest;
    private final MutableLiveData<Boolean> _mHasNoPendingTxAfterProcessing;
    private final MutableLiveData<List<TransactionInfo>> _mTransactionInfos;
    private final MutableLiveData<List<TransactionInfo>> _mPendingTransactionInfoLd;
    public LiveData<List<TransactionInfo>> mPendingTransactionInfoLd;
    public LiveData<List<TransactionInfo>> mTransactionInfoLd;
    public LiveData<TransactionInfo> mSelectedPendingRequest;
    public LiveData<Boolean> mHasNoPendingTxAfterProcessing;
    private TxServiceObserverImpl mTxServiceObserver;

    public PendingTxHelper(
            TxService txService,
            AccountInfo[] accountInfos,
            boolean returnAll,
            boolean shouldObserveTxUpdates) {
        assert txService != null;
        mTxService = txService;
        mAccountInfos = accountInfos;
        mReturnAll = returnAll;
        mTxInfos = new HashMap<>();

        mTransactionInfos = new ArrayList<>();
        mCacheTransactionInfos = new ArrayList<>();
        _mSelectedPendingRequest = new MutableLiveData<>();
        _mHasNoPendingTxAfterProcessing = new MutableLiveData<>();
        _mTransactionInfos = new MutableLiveData<>(Collections.emptyList());
        _mPendingTransactionInfoLd = new MutableLiveData<>(Collections.emptyList());
        mPendingTransactionInfoLd = _mPendingTransactionInfoLd;
        mTransactionInfoLd = _mTransactionInfos;
        mSelectedPendingRequest = _mSelectedPendingRequest;
        mHasNoPendingTxAfterProcessing = _mHasNoPendingTxAfterProcessing;

        if (shouldObserveTxUpdates) {
            mTxServiceObserver = new TxServiceObserverImpl(this);
            txService.addObserver(mTxServiceObserver);
        }
    }

    public void destroy() {
        if (mTxServiceObserver != null) {
            mTxServiceObserver.close();
            mTxServiceObserver.destroy();
            mTxServiceObserver = null;
        }
    }

    public HashMap<String, TransactionInfo[]> getTransactions() {
        return mTxInfos;
    }

    public void fetchTransactions() {
        isFetchingTx = true;
        mTransactionInfos.clear();
        mCacheTransactionInfos.clear();
        mTxInfos.clear();
        _mTransactionInfos.postValue(Collections.emptyList());
        _mSelectedPendingRequest.postValue(null);
        AsyncUtils.MultiResponseHandler allTxMultiResponse =
                new AsyncUtils.MultiResponseHandler(mAccountInfos.length);
        ArrayList<AsyncUtils.GetAllTransactionInfoResponseContext> allTxContexts =
                new ArrayList<>();
        for (AccountInfo accountInfo : mAccountInfos) {
            AsyncUtils.GetAllTransactionInfoResponseContext allTxContext =
                    new AsyncUtils.GetAllTransactionInfoResponseContext(
                            allTxMultiResponse.singleResponseComplete, accountInfo.name);
            allTxContexts.add(allTxContext);
            mTxService.getAllTransactionInfo(
                    accountInfo.accountId.coin, null, accountInfo.accountId, allTxContext);
        }
        allTxMultiResponse.setWhenAllCompletedAction(
                () -> {
                    for (AsyncUtils.GetAllTransactionInfoResponseContext allTxContext :
                            allTxContexts) {
                        ArrayList<TransactionInfo> newValue = new ArrayList<>();
                        for (TransactionInfo txInfo : allTxContext.txInfos) {
                            if (mReturnAll || txInfo.txStatus == TransactionStatus.UNAPPROVED) {
                                newValue.add(txInfo);
                            }
                        }
                        newValue.sort(sortByDateComparator);
                        TransactionInfo[] newArray = new TransactionInfo[newValue.size()];
                        newArray = newValue.toArray(newArray);
                        TransactionInfo[] value = mTxInfos.get(allTxContext.name);
                        if (value == null) {
                            mTxInfos.put(allTxContext.name, newArray);
                        } else {
                            TransactionInfo[] both =
                                    Arrays.copyOf(value, value.length + newArray.length);
                            System.arraycopy(newArray, 0, both, value.length, newArray.length);
                            mTxInfos.put(allTxContext.name, both);
                        }
                    }
                    isFetchingTx = false;
                    updateTransactionList();
                });
    }

    public void updateTxInfosMap(TransactionInfo transactionInfo) {
        if (transactionInfo.txType != TransactionStatus.UNAPPROVED) {
            for (Map.Entry<String, TransactionInfo[]> entry : mTxInfos.entrySet()) {
                TransactionInfo[] infos = entry.getValue();
                for (int i = 0; i < infos.length; i++) {
                    TransactionInfo info = infos[i];
                    if (info.id.equals(transactionInfo.id)) {
                        infos[i] = transactionInfo;
                        return;
                    }
                }
            }
        }
    }

    public void setAccountInfos(AccountInfo[] accountInfos) {
        this.mAccountInfos = accountInfos;
        fetchTransactions();
    }

    public void setAccountInfos(List<AccountInfo> accountInfos) {
        this.mAccountInfos = accountInfos.toArray(new AccountInfo[0]);
        fetchTransactions();
    }

    @Override
    public void onNewUnapprovedTx(TransactionInfo txInfo) {
        fetchTransactions();
    }

    @Override
    public void onUnapprovedTxUpdated(TransactionInfo txInfo) {
        processTx(txInfo, TxActionType.UNAPPROVED_TRANSACTION_UPDATED);
        updateTxInfosMap(txInfo);
    }

    @Override
    public void onTransactionStatusChanged(TransactionInfo txInfo) {
        processTx(txInfo, TxActionType.TRANSACTION_STATUS_CHANGED);
        updateTxInfosMap(txInfo);
    }

    public List<TransactionInfo> getPendingTransactions() {
        return mTransactionInfos;
    }

    public void setTxService(TxService txService) {
        this.mTxService = txService;
    }

    private void updateTransactionList() {
        for (TransactionInfo[] transactionInfoArr : mTxInfos.values()) {
            Collections.addAll(mTransactionInfos, transactionInfoArr);
        }
        processCachedTx();
        mTransactionInfos.sort(sortByDateComparator);
        _mTransactionInfos.postValue(mTransactionInfos);
        updatePending(mTransactionInfos);
        postTxUpdates();
    }

    private void processTx(TransactionInfo txInfo, TxActionType txActionType) {
        if (isFetchingTx) {
            mCacheTransactionInfos.add(new TransactionCacheRecord(txActionType, txInfo));
        } else {
            updateTransactionList(txInfo, txActionType);
            _mTransactionInfos.postValue(mTransactionInfos);
            updatePending(mTransactionInfos);
        }
    }

    private void processCachedTx() {
        if (!mCacheTransactionInfos.isEmpty()) {
            for (TransactionCacheRecord info : mCacheTransactionInfos) {
                updateTransactionList(info.getTransactionInfo(), info.getTxActionType());
            }
        }
        mCacheTransactionInfos.clear();
    }

    private void updateTransactionList(TransactionInfo txInfo, TxActionType txActionType) {
        if (txActionType == TxActionType.NEW_UNAPPROVED_TRANSACTION) {
            if (mTransactionInfos.isEmpty()) {
                _mSelectedPendingRequest.postValue(txInfo);
            }
            mTransactionInfos.add(txInfo);
        } else {
            if (txActionType == TxActionType.UNAPPROVED_TRANSACTION_UPDATED) {
                for (int i = 0; i < mTransactionInfos.size(); i++) {
                    TransactionInfo info = mTransactionInfos.get(i);
                    if (info.id.equals(txInfo.id)) {
                        mTransactionInfos.set(i, txInfo);
                        break;
                    }
                }
                if (getSelectedPendingRequest() != null
                        && getSelectedPendingRequest().id.equals(txInfo.id)) {
                    _mSelectedPendingRequest.postValue(txInfo);
                }
            } else if (txActionType == TxActionType.TRANSACTION_STATUS_CHANGED) {
                List<TransactionInfo> newTransactionInfos = new ArrayList<>();
                for (int i = 0; i < mTransactionInfos.size(); i++) {
                    TransactionInfo info = mTransactionInfos.get(i);
                    if (!info.id.equals(txInfo.id)) {
                        newTransactionInfos.add(info);
                    }
                }
                if (txInfo.txStatus == TransactionStatus.UNAPPROVED) {
                    newTransactionInfos.add(txInfo);
                }
                mTransactionInfos.clear();
                mTransactionInfos.addAll(newTransactionInfos);
                mTransactionInfos.sort(sortByDateComparator);
                if (((_mSelectedPendingRequest.getValue() != null
                                && _mSelectedPendingRequest.getValue().id.equals(txInfo.id))
                        || _mSelectedPendingRequest.getValue() == null)) {
                    postTxUpdates();
                }
            }
        }
    }

    public TransactionInfo getSelectedPendingRequest() {
        return mSelectedPendingRequest.getValue();
    }

    private void postTxUpdates() {
        TransactionInfo mFirstPendingInfo = getFirstUnapprovedTx();
        _mSelectedPendingRequest.postValue(mFirstPendingInfo);
        _mHasNoPendingTxAfterProcessing.postValue(mFirstPendingInfo == null);
    }

    private void updatePending(List<TransactionInfo> transactionInfos) {
        List<TransactionInfo> infos = new ArrayList<>();
        for (TransactionInfo info : transactionInfos) {
            if (info.txStatus == TransactionStatus.UNAPPROVED) {
                infos.add(info);
            }
        }
        _mPendingTransactionInfoLd.postValue(infos);
    }

    /*
     * Make sure to use get the first unapproved transaction as source list may not have one due to
     * returnAll set to true
     */
    private TransactionInfo getFirstUnapprovedTx() {
        for (TransactionInfo transactionInfo : mTransactionInfos) {
            if (transactionInfo.txStatus == TransactionStatus.UNAPPROVED) {
                return transactionInfo;
            }
        }
        return null;
    }

    private final Comparator<TransactionInfo> sortByDateComparator =
            (lhs, rhs) -> Long.compare(rhs.createdTime.microseconds, lhs.createdTime.microseconds);

    private static class TransactionCacheRecord {
        private final TxActionType mTxActionType;
        private final TransactionInfo mTransactionInfo;

        public TransactionCacheRecord(
                TxActionType mTxActionType, TransactionInfo mTransactionInfo) {
            this.mTxActionType = mTxActionType;
            this.mTransactionInfo = mTransactionInfo;
        }

        public TxActionType getTxActionType() {
            return mTxActionType;
        }

        public TransactionInfo getTransactionInfo() {
            return mTransactionInfo;
        }
    }

    private enum TxActionType {
        NEW_UNAPPROVED_TRANSACTION,
        UNAPPROVED_TRANSACTION_UPDATED,
        TRANSACTION_STATUS_CHANGED
    }
}
