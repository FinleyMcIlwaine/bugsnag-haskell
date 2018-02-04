module Network.Bugsnag.Notify
    ( notifyBugsnag
    , notifyBugsnagWith
    , notifyBugsnagThrow
    ) where

import Control.Monad (when)
import Control.Monad.Catch
import Control.Monad.IO.Class (MonadIO, liftIO)
import Network.Bugsnag.Event
import Network.Bugsnag.Exception
import Network.Bugsnag.Report
import Network.Bugsnag.Reporter
import Network.Bugsnag.Settings
import Network.Bugsnag.StackFrame

-- | Notify Bugsnag of a single exception
notifyBugsnag :: MonadIO m => BugsnagSettings m -> BugsnagException -> m ()
notifyBugsnag = notifyBugsnagWith pure

-- | Notify Bugsnag of a single exception, modifying the event
--
-- This is used to (e.g.) change severity for a specific error. Note that the
-- given function runs after any configured @'bsBeforeNotify'@.
--
notifyBugsnagWith
    :: MonadIO m
    => (BugsnagEvent -> m BugsnagEvent)
    -> BugsnagSettings m
    -> BugsnagException
    -> m ()
notifyBugsnagWith f settings exception =
    -- N.B. all notify functions should go through here. We need to maintain
    -- this as the single point where (e.g.) should-notify is checked,
    -- before-notify is applied, stack-frame filtering, etc.
    when (bugsnagShouldNotify settings) $ do
        event <- f
            . updateGroupingHash settings
            . updateStackFramesInProject settings
            . filterStackFrames settings
            =<< bsBeforeNotify settings (bugsnagEvent [exception])

        let manager = bsHttpManager settings
            apiKey = bsApiKey settings
            report = bugsnagReport [event]

        liftIO $ reportError manager apiKey report

-- | Notify Bugsnag of a single exception and re-throw it
notifyBugsnagThrow
    :: (MonadIO m, MonadThrow m) => BugsnagSettings m -> BugsnagException -> m a
notifyBugsnagThrow settings ex = notifyBugsnag settings ex >> throwM ex

updateGroupingHash :: BugsnagSettings m -> BugsnagEvent -> BugsnagEvent
updateGroupingHash settings event = event
    { beGroupingHash = bsGroupingHash settings event
    }

updateStackFramesInProject :: BugsnagSettings m -> BugsnagEvent -> BugsnagEvent
updateStackFramesInProject settings event = event
    { beExceptions = map updateExceptions $ beExceptions event
    }
  where
    updateExceptions :: BugsnagException -> BugsnagException
    updateExceptions ex = ex
        { beStacktrace = map updateStackFrames $ beStacktrace ex
        }

    updateStackFrames :: BugsnagStackFrame -> BugsnagStackFrame
    updateStackFrames sf = sf
        { bsfInProject = Just $ bsIsInProject settings $ bsfFile sf
        }

filterStackFrames :: BugsnagSettings m -> BugsnagEvent -> BugsnagEvent
filterStackFrames settings event = event
    { beExceptions = map updateExceptions $ beExceptions event
    }
  where
    updateExceptions :: BugsnagException -> BugsnagException
    updateExceptions ex = ex
        { beStacktrace = filter (bsFilterStackFrames settings) $ beStacktrace ex
        }
