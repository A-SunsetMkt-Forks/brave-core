// Copyright (c) 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.
import { copyToClipboard } from './copy-to-clipboard'

Object.assign(navigator, {
  clipboard: {
    writeText: (text: string) => {},
  },
})

describe('copyToClipboard', () => {
  it('should call navigator.clipboard.writeText', async () => {
    const mockData = 'someText'
    jest.spyOn(navigator.clipboard, 'writeText')
    await copyToClipboard(mockData)
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(mockData)
  })

  // Follow up issue to fix test via https://github.com/brave/brave-browser/issues/43583

  // it(
  //   'should throw error if navigator.clipboard.writeText '
  // + 'throws an error',
  //   async () => {
  //     jest.spyOn(navigator.clipboard, 'writeText').mockImplementation(() => {
  //       throw new Error()
  //     })
  //     await copyToClipboard('data')
  //     expect(navigator.clipboard.writeText).toThrowError()
  //   }
  // )
})
