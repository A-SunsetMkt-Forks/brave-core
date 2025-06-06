// Copyright (c) 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import styled from 'styled-components'
import Dialog from '@brave/leo/react/dialog'
import Button from '@brave/leo/react/button'
import Icon from '@brave/leo/react/icon'
import * as leo from '@brave/leo/tokens/css/variables'

import WarningCircleOutlineIcon from '../../../../assets/svg-icons/warning-circle-outline-icon.svg'
import ExamplePhraseLight from './images/example_recovery_phrase_light.png'
import ExamplePhraseDark from './images/example_recovery_phrase_dark.png'

export const BannerCard = styled.div`
  margin-top: 24px;
  margin-bottom: 40px;
  background-color: ${(p) => p.theme.color.background02};
  box-shadow: 0px 0px 8px rgba(151, 151, 151, 0.16);
  border-radius: 4px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: left;
  flex: 1;
  padding: 16px;
`

export const ImportantText = styled.span`
  font-family: 'Poppins';
  font-style: normal;
  font-weight: 600;
  font-size: 12px;
  line-height: 22px;
  color: ${(p) => p.theme.color.errorBorder};
`

export const BannerText = styled.span`
  font-family: 'Poppins';
  font-style: normal;
  font-weight: 400;
  font-size: 12px;
  line-height: 22px;
  color: ${(p) => p.theme.color.text};
`

export const CenteredRow = styled.div`
  width: 100%;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  margin-top: 12px;
  margin-bottom: 6px;
`

export const WarningCircle = styled.div`
  width: 50px;
  height: 50px;
  mask-image: url(${WarningCircleOutlineIcon});
  mask-size: contain;
  mask-repeat: no-repeat;
  mask-position: center;
  background-color: ${(p) => p.theme.color.errorBorder};
  margin-right: 16px;
`

export const Subtitle = styled.p`
  color: ${leo.color.text.secondary};
  text-align: left;
  font: ${leo.font.large.regular};
  margin: 0;
  padding: 16px 0 0 0;
  line-height: 26px;
`

export const BackupInstructions = styled.p`
  color: ${leo.color.text.primary};
  font: ${leo.font.large.semibold};
  padding: 0;
  margin: 14px 0 0;
`

export const ExampleRecoveryPhrase = styled.img.attrs(() => ({
  src: window.matchMedia('(prefers-color-scheme: dark)').matches
    ? ExamplePhraseDark
    : ExamplePhraseLight,
}))`
  width: 100%;
  height: 208px;
  margin: 54px 0;
`

export const SkipDialog = styled(Dialog).attrs({
  modal: true,
  showClose: true,
  backdropClickCloses: true,
})`
  --leo-dialog-background: ${leo.color.container.background};
  --leo-dialog-border-radius: 16px;
  --leo-dialog-color: ${leo.color.text.primary};
  --leo-dialog-padding: ${leo.spacing['4Xl']};
  --leo-dialog-width: 480px;
`

export const WarningText = styled.p`
  color: --leo-color-text-primary;
  font: ${leo.font.large.regular};
  padding: 0;
  margin: 0;
`

export const CopyButton = styled(Button).attrs({
  kind: 'plain',
})<{ isCopied?: boolean }>`
  --leo-button-color: ${(p) =>
    p.isCopied ? leo.color.systemfeedback.successText : leo.color.icon.default};
`

export const CopyText = styled.span`
  font-size: 12px;
  line-height: 20px;
  font-weight: 400 !important;
`

export const CopiedTick = styled(Icon).attrs({
  name: 'check-normal',
})`
  --leo-icon-size: 16px;
  --leo-icon-color: ${leo.color.systemfeedback.successText};
`
